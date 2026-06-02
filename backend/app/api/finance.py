import uuid
from datetime import datetime, timezone

from fastapi import APIRouter, Depends, Form, HTTPException, Request, UploadFile, File as FastAPIFile
from pydantic import BaseModel
from sqlalchemy import select, func
from sqlalchemy.ext.asyncio import AsyncSession

from app.database import get_db
from app.models import User, File, Settlement, Expense, Voucher, Invoice, Payment, Budget, BudgetItem
from app.security import get_current_user, require_module
from app.services.audit import log as audit_log
from app.services.storage import upload_file

router = APIRouter(prefix="/finance", tags=["finance"])


def _now():
    return datetime.now(timezone.utc)


async def _check_department(db: AsyncSession, user: User, target_department_id, action: str, noun: str = "财务记录"):
    """admin和财务模块用户可跨部门操作，其他用户仅限本部门"""
    if user.role == "admin":
        return
    if "finance" in (user.extra_modules or []):
        return  # 财务模块用户可跨部门审批
    # Check department membership
    if user.department_id:
        from app.models import Department
        dept = await db.get(Department, user.department_id)
        if dept and "finance" in (dept.accessible_modules or []):
            return  # 财务部门成员可跨部门操作
    if target_department_id is not None and user.department_id != target_department_id:
        raise HTTPException(403, f"不能{action}其他部门的{noun}")


# ── Pydantic Schemas ──

class SettlementCreate(BaseModel):
    project_id: str | None = None
    budget_id: str | None = None
    amount: float = 0.0
    status: str = "pending"
    settlement_date: str | None = None
    invoice_no: str = ""
    notes: str = ""


class SettlementUpdate(BaseModel):
    project_id: str | None = None
    budget_id: str | None = None
    amount: float | None = None
    status: str | None = None
    settlement_date: str | None = None
    invoice_no: str | None = None
    notes: str | None = None


class ExpenseCreate(BaseModel):
    project_id: str | None = None
    budget_id: str | None = None
    amount: float = 0.0
    category: str = "other"
    expense_type: str = "reimbursement"  # reimbursement=员工报销, direct=直接支出
    description: str = ""
    submitted_by: str | None = None
    department_id: str | None = None


class ExpenseApprove(BaseModel):
    status: str  # approved or rejected

class ExpenseUpdate(BaseModel):
    amount: float | None = None
    category: str | None = None
    expense_type: str | None = None
    description: str | None = None
    budget_id: str | None = None
    status: str | None = None


class VoucherCreate(BaseModel):
    settlement_id: str | None = None
    expense_id: str | None = None
    invoice_id: str | None = None
    type: str = "invoice"
    description: str = ""


class InvoiceCreate(BaseModel):
    project_id: str | None = None
    budget_id: str | None = None
    invoice_no: str = ""
    amount: float = 0.0
    tax_amount: float = 0.0
    tax_rate: float = 0.13
    status: str = "draft"
    issue_date: str | None = None
    due_date: str | None = None
    notes: str = ""
    seller_name: str = ""
    seller_tax_id: str = ""
    buyer_name: str = ""
    buyer_tax_id: str = ""

class InvoiceUpdate(BaseModel):
    budget_id: str | None = None
    invoice_no: str | None = None
    amount: float | None = None
    tax_amount: float | None = None
    tax_rate: float | None = None
    status: str | None = None
    issue_date: str | None = None
    due_date: str | None = None
    notes: str | None = None
    seller_name: str | None = None
    seller_tax_id: str | None = None
    buyer_name: str | None = None
    buyer_tax_id: str | None = None

class PaymentCreate(BaseModel):
    invoice_id: str | None = None
    amount: float = 0.0
    payment_date: str | None = None
    payment_method: str = "bank_transfer"
    ref_no: str = ""
    notes: str = ""


class BudgetItemCreate(BaseModel):
    category: str = "other"
    name: str = ""
    amount: float = 0.0
    color: str = "#FF0000"
    icon: str = "description"


class BudgetCreate(BaseModel):
    department_id: str | None = None
    project_id: str | None = None
    parent_id: str | None = None
    name: str = ""
    year: int = 2026
    quarter: int | None = None
    total_amount: float = 0.0
    status: str = "active"
    notes: str = ""
    items: list[BudgetItemCreate] = []

class BudgetUpdate(BaseModel):
    name: str | None = None
    year: int | None = None
    quarter: int | None = None
    total_amount: float | None = None
    status: str | None = None
    notes: str | None = None
    parent_id: str | None = None
    items: list[BudgetItemCreate] | None = None


# ── Row Serializers ──

def _settlement_row(s: Settlement) -> dict:
    return {
        "id": str(s.id),
        "project_id": str(s.project_id) if s.project_id else None,
        "budget_id": str(s.budget_id) if s.budget_id else None,
        "amount": s.amount,
        "status": s.status,
        "settlement_date": s.settlement_date.isoformat() if s.settlement_date else None,
        "invoice_no": s.invoice_no,
        "notes": s.notes,
        "department_id": str(s.department_id) if s.department_id else None,
        "created_by": str(s.created_by) if s.created_by else None,
        "created_at": s.created_at.isoformat() if s.created_at else None,
        "updated_at": s.updated_at.isoformat() if s.updated_at else None,
    }


def _expense_row(e: Expense) -> dict:
    return {
        "id": str(e.id),
        "project_id": str(e.project_id) if e.project_id else None,
        "budget_id": str(e.budget_id) if e.budget_id else None,
        "amount": e.amount,
        "category": e.category,
        "expense_type": e.expense_type,
        "description": e.description,
        "status": e.status,
        "submitted_by": str(e.submitted_by) if e.submitted_by else None,
        "department_id": str(e.department_id) if e.department_id else None,
        "created_at": e.created_at.isoformat() if e.created_at else None,
        "updated_at": e.updated_at.isoformat() if e.updated_at else None,
    }


def _voucher_row(v: Voucher) -> dict:
    return {
        "id": str(v.id),
        "settlement_id": str(v.settlement_id) if v.settlement_id else None,
        "expense_id": str(v.expense_id) if v.expense_id else None,
        "invoice_id": str(v.invoice_id) if v.invoice_id else None,
        "file_id": str(v.file_id) if v.file_id else None,
        "type": v.type,
        "description": v.description,
        "department_id": str(v.department_id) if v.department_id else None,
        "created_by": str(v.created_by) if v.created_by else None,
        "created_at": v.created_at.isoformat() if v.created_at else None,
    }


def _invoice_row(inv: Invoice) -> dict:
    return {
        "id": str(inv.id),
        "project_id": str(inv.project_id) if inv.project_id else None,
        "budget_id": str(inv.budget_id) if inv.budget_id else None,
        "invoice_no": inv.invoice_no,
        "amount": inv.amount,
        "tax_amount": inv.tax_amount,
        "tax_rate": inv.tax_rate,
        "status": inv.status,
        "issue_date": inv.issue_date.isoformat() if inv.issue_date else None,
        "due_date": inv.due_date.isoformat() if inv.due_date else None,
        "notes": inv.notes,
        "seller_name": inv.seller_name,
        "seller_tax_id": inv.seller_tax_id,
        "buyer_name": inv.buyer_name,
        "buyer_tax_id": inv.buyer_tax_id,
        "department_id": str(inv.department_id) if inv.department_id else None,
        "created_at": inv.created_at.isoformat() if inv.created_at else None,
        "updated_at": inv.updated_at.isoformat() if inv.updated_at else None,
    }

def _payment_row(p: Payment) -> dict:
    return {
        "id": str(p.id),
        "invoice_id": str(p.invoice_id) if p.invoice_id else None,
        "amount": p.amount,
        "payment_date": p.payment_date.isoformat() if p.payment_date else None,
        "payment_method": p.payment_method,
        "ref_no": p.ref_no,
        "notes": p.notes,
        "department_id": str(p.department_id) if p.department_id else None,
        "created_at": p.created_at.isoformat() if p.created_at else None,
    }


def _budget_item_row(item: BudgetItem) -> dict:
    return {
        "id": str(item.id),
        "category": item.category,
        "name": item.name,
        "amount": item.amount,
        "used_amount": item.used_amount,
        "color": item.color,
        "icon": item.icon,
    }


async def _budget_row(b: Budget, db: AsyncSession) -> dict:
    items_result = await db.execute(select(BudgetItem).where(BudgetItem.budget_id == b.id))
    budget_items = items_result.scalars().all()
    dept_name = None
    if b.department_id:
        from app.models import Department
        dept = await db.get(Department, b.department_id)
        dept_name = dept.name if dept else None
    return {
        "id": str(b.id),
        "department_id": str(b.department_id) if b.department_id else None,
        "department_name": dept_name,
        "project_id": str(b.project_id) if b.project_id else None,
        "parent_id": str(b.parent_id) if b.parent_id else None,
        "name": b.name,
        "year": b.year,
        "quarter": b.quarter,
        "total_amount": b.total_amount,
        "used_amount": b.used_amount,
        "status": b.status,
        "notes": b.notes,
        "updated_at": b.updated_at.isoformat() if b.updated_at else None,
        "created_at": b.created_at.isoformat() if b.created_at else None,
        "items": [_budget_item_row(item) for item in budget_items],
    }


def _budget_date_range(b):
    """Return (start, end) UTC datetime range for a budget based on year+quarter."""
    if not b.year:
        return None, None
    if b.quarter:
        q = b.quarter - 1
        start_month = q * 3 + 1
        start = datetime(b.year, start_month, 1, tzinfo=timezone.utc)
        if q < 3:
            end = datetime(b.year, start_month + 3, 1, tzinfo=timezone.utc)
        else:
            end = datetime(b.year + 1, 1, 1, tzinfo=timezone.utc)
        return start, end
    return datetime(b.year, 1, 1, tzinfo=timezone.utc), datetime(b.year + 1, 1, 1, tzinfo=timezone.utc)


async def _recalc_budget_usage(db: AsyncSession):
    """Recalculate used_amount for all active budgets using explicit budget_id linkage.
    Upward propagation: parent.used_amount = sum of children.used_amount."""
    all_budgets = (await db.execute(select(Budget).where(Budget.status == "active"))).scalars().all()
    if not all_budgets:
        return

    budget_ids = [b.id for b in all_budgets]
    budget_map = {str(b.id): b for b in all_budgets}

    # Reset all budgets to zero before recalc
    for b in all_budgets:
        b.used_amount = 0.0

    # Step 0: Auto-assign budget_id for expenses that don't have one yet
    unlinked = (await db.execute(
        select(Expense).where(
            Expense.budget_id.is_(None),
            Expense.status.in_(["approved", "paid"]),
        )
    )).scalars().all()
    if unlinked:
        leaf_budgets = [b for b in all_budgets if b.quarter is not None and b.department_id is not None]
        for exp in unlinked:
            if not exp.department_id:
                continue
            for b in leaf_budgets:
                if b.department_id != exp.department_id:
                    continue
                ym_start, ym_end = _budget_date_range(b)
                if ym_start and not (ym_start <= exp.created_at < ym_end):
                    continue
                exp.budget_id = b.id
                break
            # If no match, auto-create full tree: Year -> Quarter -> Department
            if exp.budget_id is None:
                ey = exp.created_at.year if exp.created_at else datetime.now(timezone.utc).year
                eq = ((exp.created_at.month - 1) // 3 + 1) if exp.created_at else 1
                # 1. Year root
                root = next((b for b in all_budgets if b.parent_id is None and b.year == ey and b.quarter is None and b.department_id is None), None)
                if root is None:
                    root = Budget(name=f"{ey}年总预算", year=ey, total_amount=0.0, status="active", created_by=exp.submitted_by)
                    db.add(root); await db.flush()
                    all_budgets.append(root); budget_ids.append(root.id); budget_map[str(root.id)] = root
                # 2. Quarter budget under root
                qb = next((b for b in all_budgets if b.parent_id == root.id and b.quarter == eq and b.department_id is None), None)
                if qb is None:
                    qb = Budget(name=f"{ey}年Q{eq}", parent_id=root.id, year=ey, quarter=eq, total_amount=0.0, status="active", created_by=exp.submitted_by)
                    db.add(qb); await db.flush()
                    all_budgets.append(qb); budget_ids.append(qb.id); budget_map[str(qb.id)] = qb
                # 3. Department budget under quarter
                from app.models import Department
                dept_obj = await db.get(Department, exp.department_id)
                dept_name = dept_obj.name if dept_obj else "未分类"
                uncat = next((b for b in all_budgets if b.parent_id == qb.id and b.department_id == exp.department_id), None)
                if uncat is None:
                    uncat = Budget(name=f"{ey}年Q{eq}{dept_name}", parent_id=qb.id, department_id=exp.department_id,
                                   year=ey, quarter=eq, total_amount=0.0, status="active", created_by=exp.submitted_by)
                    db.add(uncat); await db.flush()
                    all_budgets.append(uncat); budget_ids.append(uncat.id); budget_map[str(uncat.id)] = uncat
                exp.budget_id = uncat.id
        await db.commit()

    # Step 1: Expenses grouped by budget_id (approved or paid)
    exp_rows = (await db.execute(
        select(Expense.budget_id, func.coalesce(func.sum(Expense.amount), 0.0))
        .where(Expense.budget_id.in_(budget_ids), Expense.status.in_(["approved", "paid"]))
        .group_by(Expense.budget_id)
    )).all()
    for bid, total in exp_rows:
        if str(bid) in budget_map:
            budget_map[str(bid)].used_amount += float(total or 0)

    # Step 2: Per-item used_amount from expenses matching category
    all_items = (await db.execute(
        select(BudgetItem).where(BudgetItem.budget_id.in_(budget_ids))
    )).scalars().all()
    for item in all_items:
        item.used_amount = (await db.execute(
            select(func.coalesce(func.sum(Expense.amount), 0.0)).where(
                Expense.budget_id == item.budget_id,
                Expense.category == item.category,
                Expense.status.in_(["approved", "paid"]),
            )
        )).scalar() or 0.0

    # Step 4: Upward propagation — parent used_amount = sum of children
    children_map = {}
    for b in all_budgets:
        if b.parent_id:
            children_map.setdefault(str(b.parent_id), []).append(b)
    changed = True
    while changed:
        changed = False
        for b in all_budgets:
            if str(b.id) in children_map:
                child_sum = sum(c.used_amount for c in children_map[str(b.id)])
                if abs(b.used_amount - child_sum) > 0.01:
                    b.used_amount = child_sum
                    changed = True
    await db.commit()


# ── Settlements ──

@router.get("/settlements")
async def list_settlements(
    status: str = "",
    limit: int = 50,
    offset: int = 0,
    db: AsyncSession = Depends(get_db),
    user: User = Depends(get_current_user),
    _m: User = Depends(require_module("finance")),
):
    query = select(Settlement).order_by(Settlement.updated_at.desc())
    if user.role != "admin":
        if user.department_id:
            query = query.where(Settlement.department_id == user.department_id)
        else:
            query = query.where(Settlement.created_by == user.id)
    if status:
        query = query.where(Settlement.status == status)
    result = await db.execute(query.offset(offset).limit(limit))
    return {"items": [_settlement_row(s) for s in result.scalars().all()]}


@router.post("/settlements")
async def create_settlement(
    body: SettlementCreate,
    request: Request = None,
    db: AsyncSession = Depends(get_db),
    user: User = Depends(get_current_user),
    _m: User = Depends(require_module("finance")),
):
    project_id = uuid.UUID(body.project_id) if body.project_id else None
    budget_id = uuid.UUID(body.budget_id) if body.budget_id else None
    settlement_date = datetime.fromisoformat(body.settlement_date) if body.settlement_date else None
    s = Settlement(
        project_id=project_id,
        budget_id=budget_id,
        amount=body.amount,
        status=body.status,
        settlement_date=settlement_date,
        invoice_no=body.invoice_no,
        notes=body.notes,
        department_id=user.department_id,
        created_by=user.id,
    )
    db.add(s)
    await db.commit()
    await _recalc_budget_usage(db)
    await db.refresh(s)
    await audit_log(db, user, "settlement_create", "settlement", s.id, s.invoice_no, request=request)
    return _settlement_row(s)


@router.get("/settlements/{settlement_id}")
async def get_settlement(
    settlement_id: str,
    db: AsyncSession = Depends(get_db),
    user: User = Depends(get_current_user),
    _m: User = Depends(require_module("finance")),
):
    result = await db.execute(select(Settlement).where(Settlement.id == settlement_id))
    s = result.scalar_one_or_none()
    if not s:
        raise HTTPException(404, "结算不存在")
    return _settlement_row(s)


@router.put("/settlements/{settlement_id}")
async def update_settlement(
    settlement_id: str,
    body: SettlementUpdate,
    request: Request = None,
    db: AsyncSession = Depends(get_db),
    user: User = Depends(get_current_user),
    _m: User = Depends(require_module("finance")),
):
    result = await db.execute(select(Settlement).where(Settlement.id == settlement_id))
    s = result.scalar_one_or_none()
    if not s:
        raise HTTPException(404, "结算不存在")
    await _check_department(db, user, s.department_id, "编辑")
    old_status = s.status
    for k, v in body.model_dump(exclude_none=True).items():
        if k == "project_id" and v is not None:
            setattr(s, k, uuid.UUID(v) if v else None)
        elif k == "budget_id" and v is not None:
            setattr(s, k, uuid.UUID(v) if v else None)
        elif k == "settlement_date" and v is not None:
            setattr(s, k, datetime.fromisoformat(v) if v else None)
        elif v is not None:
            setattr(s, k, v)
    s.updated_at = _now()
    await db.commit()
    if old_status not in ("completed", "settled") and s.status in ("completed", "settled"):
        await _recalc_budget_usage(db)
    await db.refresh(s)
    await audit_log(db, user, "settlement_update", "settlement", s.id, s.invoice_no, request=request)
    return _settlement_row(s)


@router.delete("/settlements/{settlement_id}")
async def delete_settlement(
    settlement_id: str,
    request: Request = None,
    db: AsyncSession = Depends(get_db),
    user: User = Depends(get_current_user),
    _m: User = Depends(require_module("finance")),
):
    result = await db.execute(select(Settlement).where(Settlement.id == settlement_id))
    s = result.scalar_one_or_none()
    if not s:
        raise HTTPException(404, "结算不存在")
    await _check_department(db, user, s.department_id, "删除")
    await db.delete(s)
    await db.commit()
    await _recalc_budget_usage(db)
    await audit_log(db, user, "settlement_delete", "settlement", s.id, s.invoice_no, request=request)
    return {"ok": True}


# ── Expenses ──

@router.get("/expenses")
async def list_expenses(
    category: str = "",
    status: str = "",
    expense_type: str = "",
    limit: int = 50,
    offset: int = 0,
    db: AsyncSession = Depends(get_db),
    user: User = Depends(get_current_user),
):
    query = select(Expense).order_by(Expense.updated_at.desc())
    # Check if user has finance module (can see all) or only expense (own records)
    can_see_all = user.role == "admin"
    if not can_see_all and user.department_id:
        from app.models import Department
        dept = await db.get(Department, user.department_id)
        if dept and "finance" in (dept.accessible_modules or []):
            can_see_all = True
    if "finance" in (user.extra_modules or []):
        can_see_all = True
    if not can_see_all:
        query = query.where(Expense.submitted_by == user.id)
    if category:
        query = query.where(Expense.category == category)
    if status:
        query = query.where(Expense.status == status)
    if expense_type:
        query = query.where(Expense.expense_type == expense_type)
    result = await db.execute(query.offset(offset).limit(limit))
    return {"items": [_expense_row(e) for e in result.scalars().all()]}


@router.post("/expenses")
async def create_expense(
    body: ExpenseCreate,
    request: Request = None,
    db: AsyncSession = Depends(get_db),
    user: User = Depends(get_current_user),
    _m: User = Depends(require_module("expense")),
):
    project_id = uuid.UUID(body.project_id) if body.project_id else None
    budget_id = uuid.UUID(body.budget_id) if body.budget_id else None
    submitted_by = uuid.UUID(body.submitted_by) if body.submitted_by else user.id
    status = "paid" if body.expense_type == "direct" else "pending"
    e = Expense(
        project_id=project_id,
        budget_id=budget_id,
        amount=body.amount,
        category=body.category,
        expense_type=body.expense_type,
        description=body.description,
        status=status,
        submitted_by=submitted_by,
        department_id=user.department_id if user.department_id else body.department_id,
    )
    db.add(e)
    await db.commit()
    await db.refresh(e)
    if status == "paid":
        await _recalc_budget_usage(db)
    await audit_log(db, user, "expense_create", "expense", e.id, body.category, request=request)
    return _expense_row(e)


@router.put("/expenses/{expense_id}")
async def approve_expense(
    expense_id: str,
    body: ExpenseUpdate,
    request: Request = None,
    db: AsyncSession = Depends(get_db),
    user: User = Depends(get_current_user),
    _m: User = Depends(require_module("finance")),
):
    result = await db.execute(select(Expense).where(Expense.id == expense_id))
    e = result.scalar_one_or_none()
    if not e:
        raise HTTPException(404, "报销不存在")
    await _check_department(db, user, e.department_id, "审批")
    old_status = e.status
    update_data = body.model_dump(exclude_unset=True)
    status_changed = False
    for k, v in update_data.items():
        if k == "budget_id":
            setattr(e, k, uuid.UUID(v) if v else None)
        elif k == "status" and v is not None:
            if v not in ("approved", "rejected", "paid", "pending"):
                raise HTTPException(400, "无效状态")
            e.status = v
            status_changed = True
        elif v is not None:
            setattr(e, k, v)
    e.updated_at = _now()
    await db.commit()
    if status_changed or e.status in ("approved", "paid"):
        await _recalc_budget_usage(db)
    await db.refresh(e)
    action = f"expense_{e.status}" if status_changed else "expense_update"
    await audit_log(db, user, action, "expense", e.id, e.category, request=request)
    return _expense_row(e)


@router.delete("/expenses/{expense_id}")
async def delete_expense(
    expense_id: str,
    request: Request = None,
    db: AsyncSession = Depends(get_db),
    user: User = Depends(get_current_user),
    _m: User = Depends(require_module("finance")),
):
    result = await db.execute(select(Expense).where(Expense.id == expense_id))
    e = result.scalar_one_or_none()
    if not e:
        raise HTTPException(404, "报销不存在")
    await _check_department(db, user, e.department_id, "删除")
    await db.delete(e)
    await db.commit()
    await _recalc_budget_usage(db)
    await audit_log(db, user, "expense_delete", "expense", e.id, e.category, request=request)
    return {"ok": True}


# ── Vouchers ──

@router.get("/vouchers")
async def list_vouchers(
    settlement_id: str = "",
    expense_id: str = "",
    invoice_id: str = "",
    limit: int = 50,
    offset: int = 0,
    db: AsyncSession = Depends(get_db),
    user: User = Depends(get_current_user),
    _m: User = Depends(require_module("finance")),
):
    query = select(Voucher).order_by(Voucher.created_at.desc())
    if user.role != "admin":
        if user.department_id:
            query = query.where(Voucher.department_id == user.department_id)
        else:
            query = query.where(Voucher.created_by == user.id)
    if settlement_id:
        query = query.where(Voucher.settlement_id == settlement_id)
    if expense_id:
        query = query.where(Voucher.expense_id == expense_id)
    if invoice_id:
        query = query.where(Voucher.invoice_id == invoice_id)
    result = await db.execute(query.offset(offset).limit(limit))
    return {"items": [_voucher_row(v) for v in result.scalars().all()]}


@router.post("/vouchers")
async def create_voucher(
    body: VoucherCreate,
    request: Request = None,
    db: AsyncSession = Depends(get_db),
    user: User = Depends(get_current_user),
    _m: User = Depends(require_module("finance")),
):
    settlement_id = uuid.UUID(body.settlement_id) if body.settlement_id else None
    expense_id = uuid.UUID(body.expense_id) if body.expense_id else None
    invoice_id = uuid.UUID(body.invoice_id) if body.invoice_id else None
    v = Voucher(
        settlement_id=settlement_id,
        expense_id=expense_id,
        invoice_id=invoice_id,
        type=body.type,
        description=body.description,
        department_id=user.department_id,
        created_by=user.id,
    )
    db.add(v)
    await db.commit()
    await db.refresh(v)
    await audit_log(db, user, "voucher_create", "voucher", v.id, body.description, request=request)
    return _voucher_row(v)


@router.post("/vouchers/upload")
async def upload_voucher(
    file: UploadFile = FastAPIFile(...),
    type: str = Form("invoice"),
    description: str = Form(""),
    settlement_id: str = Form(""),
    expense_id: str = Form(""),
    invoice_id: str = Form(""),
    request: Request = None,
    db: AsyncSession = Depends(get_db),
    user: User = Depends(get_current_user),
    _m: User = Depends(require_module("finance")),
):
    content_bytes = await file.read()
    storage_path = f"vouchers/{uuid.uuid4()}/{file.filename}"

    await upload_file(storage_path, content_bytes, file.content_type or "application/octet-stream")

    file_record = File(
        name=file.filename,
        is_folder=False,
        mime_type=file.content_type or "application/pdf",
        size_bytes=len(content_bytes),
        storage_path=storage_path,
        uploaded_by=user.id,
    )
    db.add(file_record)
    await db.commit()
    await db.refresh(file_record)

    sid = uuid.UUID(settlement_id) if settlement_id else None
    eid = uuid.UUID(expense_id) if expense_id else None
    iid = uuid.UUID(invoice_id) if invoice_id else None
    v = Voucher(
        settlement_id=sid,
        expense_id=eid,
        invoice_id=iid,
        file_id=file_record.id,
        type=type,
        description=description.strip() or file.filename,
        department_id=user.department_id,
        created_by=user.id,
    )
    db.add(v)
    await db.commit()
    await db.refresh(v)
    await audit_log(db, user, "voucher_upload", "voucher", v.id, v.description, request=request)
    return _voucher_row(v)


@router.delete("/vouchers/{voucher_id}")
async def delete_voucher(
    voucher_id: str,
    request: Request = None,
    db: AsyncSession = Depends(get_db),
    user: User = Depends(get_current_user),
    _m: User = Depends(require_module("finance")),
):
    result = await db.execute(select(Voucher).where(Voucher.id == voucher_id))
    v = result.scalar_one_or_none()
    if not v:
        raise HTTPException(404, "凭证不存在")
    await _check_department(db, user, v.department_id, "删除")
    await db.delete(v)
    await db.commit()
    await audit_log(db, user, "voucher_delete", "voucher", v.id, v.description, request=request)
    return {"ok": True}


# ── Invoices ──

@router.get("/invoices")
async def list_invoices(
    project_id: str = "",
    status: str = "",
    search: str = "",
    limit: int = 50,
    offset: int = 0,
    db: AsyncSession = Depends(get_db),
    user: User = Depends(get_current_user),
    _m: User = Depends(require_module("finance")),
):
    query = select(Invoice).order_by(Invoice.updated_at.desc())
    # Finance module users can see all invoices for approval
    if project_id:
        query = query.where(Invoice.project_id == project_id)
    if status:
        query = query.where(Invoice.status == status)
    if search:
        query = query.where(
            Invoice.invoice_no.ilike(f"%{search}%")
            | Invoice.notes.ilike(f"%{search}%")
            | Invoice.seller_name.ilike(f"%{search}%")
            | Invoice.buyer_name.ilike(f"%{search}%")
        )
    result = await db.execute(query.offset(offset).limit(limit))
    return {"items": [_invoice_row(i) for i in result.scalars().all()]}


@router.post("/invoices")
async def create_invoice(
    body: InvoiceCreate,
    request: Request = None,
    db: AsyncSession = Depends(get_db),
    user: User = Depends(get_current_user),
    _m: User = Depends(require_module("finance")),
):
    project_id = uuid.UUID(body.project_id) if body.project_id else None
    budget_id = uuid.UUID(body.budget_id) if body.budget_id else None
    issue_date = datetime.fromisoformat(body.issue_date) if body.issue_date else None
    due_date = datetime.fromisoformat(body.due_date) if body.due_date else None
    i = Invoice(
        project_id=project_id, budget_id=budget_id, invoice_no=body.invoice_no, amount=body.amount,
        tax_amount=body.tax_amount, tax_rate=body.tax_rate, status=body.status,
        issue_date=issue_date, due_date=due_date, notes=body.notes,
        seller_name=body.seller_name, seller_tax_id=body.seller_tax_id,
        buyer_name=body.buyer_name, buyer_tax_id=body.buyer_tax_id,
        department_id=user.department_id, created_by=user.id,
    )
    db.add(i)
    await db.commit()
    await db.refresh(i)
    await audit_log(db, user, "invoice_create", "invoice", i.id, i.invoice_no, request=request)
    return _invoice_row(i)


@router.put("/invoices/{invoice_id}")
async def update_invoice(
    invoice_id: str,
    body: InvoiceUpdate,
    request: Request = None,
    db: AsyncSession = Depends(get_db),
    user: User = Depends(get_current_user),
    _m: User = Depends(require_module("finance")),
):
    result = await db.execute(select(Invoice).where(Invoice.id == invoice_id))
    i = result.scalar_one_or_none()
    if not i:
        raise HTTPException(404, "发票不存在")
    await _check_department(db, user, i.department_id, "修改")
    for k, v in body.model_dump(exclude_unset=True).items():
        if k in ("issue_date", "due_date") and v is not None:
            setattr(i, k, datetime.fromisoformat(v))
        elif k == "budget_id" and v is not None:
            setattr(i, k, uuid.UUID(v) if v else None)
        elif v is not None and k not in ("issue_date", "due_date", "budget_id"):
            setattr(i, k, v)
    if body.amount is not None:
        await _sync_invoice_status(uuid.UUID(invoice_id), db)
    await db.commit()
    await db.refresh(i)
    await audit_log(db, user, "invoice_update", "invoice", i.id, i.invoice_no, request=request)
    return _invoice_row(i)


@router.delete("/invoices/{invoice_id}")
async def delete_invoice(
    invoice_id: str,
    request: Request = None,
    db: AsyncSession = Depends(get_db),
    user: User = Depends(get_current_user),
    _m: User = Depends(require_module("finance")),
):
    result = await db.execute(select(Invoice).where(Invoice.id == invoice_id))
    i = result.scalar_one_or_none()
    if not i:
        raise HTTPException(404, "发票不存在")
    await _check_department(db, user, i.department_id, "删除")
    await db.delete(i)
    await db.commit()
    await audit_log(db, user, "invoice_delete", "invoice", i.id, i.invoice_no, request=request)
    return {"ok": True}


# ── Payments ──

async def _sync_invoice_status(invoice_id: uuid.UUID, db: AsyncSession):
    """Update invoice status based on total payments."""
    result = await db.execute(
        select(func.coalesce(func.sum(Payment.amount), 0.0)).where(Payment.invoice_id == invoice_id)
    )
    paid = result.scalar() or 0.0
    inv = (await db.execute(select(Invoice).where(Invoice.id == invoice_id))).scalar_one_or_none()
    if inv:
        if paid >= inv.amount and inv.amount > 0:
            inv.status = "paid"
        elif paid > 0:
            inv.status = "partial"
        elif paid == 0:
            inv.status = "issued" if inv.status != "draft" else inv.status
        await db.commit()


@router.get("/payments")
async def list_payments(
    invoice_id: str = "",
    limit: int = 50,
    offset: int = 0,
    db: AsyncSession = Depends(get_db),
    user: User = Depends(get_current_user),
    _m: User = Depends(require_module("finance")),
):
    query = select(Payment).order_by(Payment.created_at.desc())
    if user.role != "admin":
        if user.department_id:
            query = query.where(Payment.department_id == user.department_id)
        else:
            query = query.where(Payment.created_by == user.id)
    if invoice_id:
        query = query.where(Payment.invoice_id == invoice_id)
    result = await db.execute(query.offset(offset).limit(limit))
    return {"items": [_payment_row(p) for p in result.scalars().all()]}


@router.post("/payments")
async def create_payment(
    body: PaymentCreate,
    request: Request = None,
    db: AsyncSession = Depends(get_db),
    user: User = Depends(get_current_user),
    _m: User = Depends(require_module("finance")),
):
    invoice_id = uuid.UUID(body.invoice_id) if body.invoice_id else None
    payment_date = datetime.fromisoformat(body.payment_date) if body.payment_date else None
    p = Payment(
        invoice_id=invoice_id, amount=body.amount, payment_date=payment_date,
        payment_method=body.payment_method, ref_no=body.ref_no, notes=body.notes,
        department_id=user.department_id, created_by=user.id,
    )
    db.add(p)
    await db.commit()
    await db.refresh(p)
    if invoice_id:
        await _sync_invoice_status(invoice_id, db)
    await audit_log(db, user, "payment_create", "payment", p.id, f"¥{p.amount}", request=request)
    return _payment_row(p)


@router.delete("/payments/{payment_id}")
async def delete_payment(
    payment_id: str,
    request: Request = None,
    db: AsyncSession = Depends(get_db),
    user: User = Depends(get_current_user),
    _m: User = Depends(require_module("finance")),
):
    result = await db.execute(select(Payment).where(Payment.id == payment_id))
    p = result.scalar_one_or_none()
    if not p:
        raise HTTPException(404, "收款不存在")
    await _check_department(db, user, p.department_id, "删除")
    inv_id = p.invoice_id
    await db.delete(p)
    await db.commit()
    if inv_id:
        await _sync_invoice_status(inv_id, db)
    await audit_log(db, user, "payment_delete", "payment", p.id, f"¥{p.amount}", request=request)
    return {"ok": True}


# ── Budgets ──

@router.get("/budgets")
async def list_budgets(
    department_id: str = "",
    parent_id: str = "",
    year: int = 0,
    db: AsyncSession = Depends(get_db),
    user: User = Depends(get_current_user),
    _m: User = Depends(require_module("finance")),
):
    query = select(Budget).order_by(Budget.updated_at.desc())
    # Finance department users see all budgets; others only see their own department
    can_see_all = user.role == "admin"
    if not can_see_all and user.department_id:
        from app.models import Department
        dept = await db.get(Department, user.department_id)
        if dept and "finance" in (dept.accessible_modules or []):
            can_see_all = True
    if "finance" in (user.extra_modules or []):
        can_see_all = True
    if not can_see_all and user.department_id:
        query = query.where(Budget.department_id == user.department_id)
    if department_id:
        query = query.where(Budget.department_id == department_id)
    if parent_id:
        query = query.where(Budget.parent_id == parent_id)
    if year:
        query = query.where(Budget.year == year)
    result = await db.execute(query)
    items = []
    for b in result.scalars().all():
        items.append(await _budget_row(b, db))
    return {"items": items}


@router.post("/budgets")
async def create_budget(
    body: BudgetCreate,
    request: Request = None,
    db: AsyncSession = Depends(get_db),
    user: User = Depends(get_current_user),
    _m: User = Depends(require_module("finance")),
):
    # Only Level 3 (with explicit department_id) budgets should have department_id
    project_id = uuid.UUID(body.project_id) if body.project_id else None
    parent_id = uuid.UUID(body.parent_id) if body.parent_id else None
    dept_id = uuid.UUID(body.department_id) if body.department_id else None

    # Auto-calculate total_amount from items if items are provided
    total_amount = body.total_amount
    if body.items:
        total_amount = sum(item.amount for item in body.items)

    # Validate: project budget must not exceed department budget
    if project_id and dept_id:
        dept_result = await db.execute(
            select(func.coalesce(func.sum(Budget.total_amount), 0.0)).where(
                Budget.department_id == dept_id,
                Budget.project_id.is_(None),
                Budget.status == "active",
                Budget.year == body.year,
            )
        )
        dept_budget = dept_result.scalar() or 0.0
        if dept_budget > 0:
            proj_result = await db.execute(
                select(func.coalesce(func.sum(Budget.total_amount), 0.0)).where(
                    Budget.department_id == dept_id,
                    Budget.project_id.isnot(None),
                    Budget.status == "active",
                    Budget.year == body.year,
                )
            )
            proj_budgets = proj_result.scalar() or 0.0
            if proj_budgets + total_amount > dept_budget:
                raise HTTPException(400, f"项目预算总和({proj_budgets + total_amount:.0f})超过部门预算({dept_budget:.0f})")

    # Validate: child budgets sum must not exceed parent budget
    if parent_id:
        parent_result = await db.execute(select(Budget).where(Budget.id == parent_id))
        parent_b = parent_result.scalar_one_or_none()
        if parent_b:
            siblings_result = await db.execute(
                select(func.coalesce(func.sum(Budget.total_amount), 0.0)).where(
                    Budget.parent_id == parent_id,
                    Budget.status == "active",
                )
            )
            siblings_total = siblings_result.scalar() or 0.0
            if siblings_total + total_amount > parent_b.total_amount:
                raise HTTPException(400, f"子预算总和({siblings_total + total_amount:.0f})超过父预算总额({parent_b.total_amount:.0f})")

    # ── Structural validation ──
    if parent_id is None:
        # Level 1: root budget — one per year
        existing_root = await db.execute(
            select(Budget).where(Budget.parent_id.is_(None), Budget.year == body.year, Budget.status == "active")
        )
        if existing_root.scalar_one_or_none():
            raise HTTPException(400, f"{body.year}年已存在总预算，每年只能创建一个")
    elif body.quarter is None:
        raise HTTPException(400, "季度不能为空")
    elif body.department_id is None:
        # Level 2: quarter budget — max 4 per year, no duplicate quarters
        siblings = (await db.execute(
            select(Budget).where(Budget.parent_id == parent_id, Budget.status == "active")
        )).scalars().all()
        if len(siblings) >= 4:
            raise HTTPException(400, f"每个年度最多创建4个季度预算")
        for sib in siblings:
            if sib.quarter == body.quarter:
                raise HTTPException(400, f"Q{body.quarter}季度预算已存在，不能重复创建")
    elif body.quarter is not None and body.department_id is not None:
        # Level 3: department budget — max N+1, no duplicate departments
        from app.models import Department
        dept_count = (await db.execute(select(func.count(Department.id)))).scalar() or 0
        max_dept_budgets = dept_count + 1
        siblings = (await db.execute(
            select(Budget).where(Budget.parent_id == parent_id, Budget.status == "active")
        )).scalars().all()
        if len(siblings) >= max_dept_budgets:
            raise HTTPException(400, f"每个季度最多创建{max_dept_budgets}个部门预算")
        for sib in siblings:
            if sib.department_id == dept_id:
                raise HTTPException(400, "该部门的季度预算已存在，不能重复创建")

    b = Budget(
        department_id=dept_id, project_id=project_id, parent_id=parent_id, name=body.name,
        year=body.year, quarter=body.quarter, total_amount=total_amount,
        status=body.status, notes=body.notes, created_by=user.id,
    )
    db.add(b)
    await db.commit()
    await db.refresh(b)

    # Create budget items
    for item_data in body.items:
        item = BudgetItem(
            budget_id=b.id,
            category=item_data.category,
            name=item_data.name,
            amount=item_data.amount,
            color=item_data.color,
            icon=item_data.icon,
        )
        db.add(item)
    if body.items:
        await db.commit()

    await _recalc_budget_usage(db)
    await db.refresh(b)
    await audit_log(db, user, "budget_create", "budget", b.id, b.name, request=request)
    return await _budget_row(b, db)


@router.put("/budgets/{budget_id}")
async def update_budget(
    budget_id: str,
    body: BudgetUpdate,
    request: Request = None,
    db: AsyncSession = Depends(get_db),
    user: User = Depends(get_current_user),
    _m: User = Depends(require_module("finance")),
):
    result = await db.execute(select(Budget).where(Budget.id == budget_id))
    b = result.scalar_one_or_none()
    if not b:
        raise HTTPException(404, "预算不存在")
    await _check_department(db, user, b.department_id, "修改", "预算")
    update_data = body.model_dump(exclude_unset=True)
    items_data = update_data.pop("items", None)

    for k, v in update_data.items():
        if v is not None:
            setattr(b, k, v)

    # Sync budget items if provided
    if items_data is not None:
        # Delete existing items
        existing = await db.execute(select(BudgetItem).where(BudgetItem.budget_id == b.id))
        for old_item in existing.scalars().all():
            await db.delete(old_item)
        # Create new items
        total = 0.0
        for item_data in items_data:
            item = BudgetItem(
                budget_id=b.id,
                category=item_data["category"],
                name=item_data.get("name", ""),
                amount=item_data.get("amount", 0.0),
                color=item_data.get("color", "#FF0000"),
                icon=item_data.get("icon", "description"),
            )
            db.add(item)
            total += item_data.get("amount", 0.0)
        b.total_amount = total

    # Validate: budget with parent must not exceed parent total
    if b.parent_id:
        parent = await db.execute(select(Budget).where(Budget.id == b.parent_id))
        parent_b = parent.scalar_one_or_none()
        if parent_b:
            sib_result = await db.execute(
                select(func.coalesce(func.sum(Budget.total_amount), 0.0)).where(
                    Budget.parent_id == b.parent_id,
                    Budget.id != b.id,
                    Budget.status == "active",
                )
            )
            sib_total = sib_result.scalar() or 0.0
            if sib_total + b.total_amount > parent_b.total_amount:
                raise HTTPException(400, f"子预算总和({sib_total + b.total_amount:.0f})超过父预算总额({parent_b.total_amount:.0f})")

    # Validate: parent budget must not be less than sum of children
    children_result = await db.execute(
        select(func.coalesce(func.sum(Budget.total_amount), 0.0)).where(
            Budget.parent_id == b.id,
            Budget.status == "active",
        )
    )
    children_sum = children_result.scalar() or 0.0
    if children_sum > b.total_amount:
        raise HTTPException(400, f"预算总额({b.total_amount:.0f})不能小于子预算总和({children_sum:.0f})")

    await db.commit()
    await _recalc_budget_usage(db)
    await db.refresh(b)
    await audit_log(db, user, "budget_update", "budget", b.id, b.name, request=request)
    return await _budget_row(b, db)


@router.delete("/budgets/{budget_id}")
async def delete_budget(
    budget_id: str,
    request: Request = None,
    db: AsyncSession = Depends(get_db),
    user: User = Depends(get_current_user),
    _m: User = Depends(require_module("finance")),
):
    result = await db.execute(select(Budget).where(Budget.id == budget_id))
    b = result.scalar_one_or_none()
    if not b:
        raise HTTPException(404, "预算不存在")
    await _check_department(db, user, b.department_id, "删除", "预算")
    await db.delete(b)
    await db.commit()
    await audit_log(db, user, "budget_delete", "budget", b.id, b.name, request=request)
    return {"ok": True}


@router.get("/budgets/summary")
async def budgets_summary(
    db: AsyncSession = Depends(get_db),
    user: User = Depends(get_current_user),
    _m: User = Depends(require_module("finance")),
):
    query = select(Budget).where(Budget.status == "active")
    # Non-admin non-finance users see only their department budgets + shared (null dept) budgets
    can_see_all = user.role == "admin"
    if not can_see_all and user.department_id:
        from app.models import Department
        dept = await db.get(Department, user.department_id)
        if dept and "finance" in (dept.accessible_modules or []):
            can_see_all = True
    if "finance" in (user.extra_modules or []):
        can_see_all = True
    if not can_see_all and user.department_id:
        query = query.where(
            (Budget.department_id == user.department_id) | (Budget.department_id == None)
        )

    budgets = (await db.execute(query)).scalars().all()

    # Only count root budgets (parent_id is None) to avoid double-counting
    root_budgets = [b for b in budgets if b.parent_id is None]

    total_budget = 0.0
    total_used = 0.0
    items = []
    allocated = 0.0
    categorized_used = 0.0

    for b in root_budgets:
        total_budget += b.total_amount
        total_used += b.used_amount
        budget_items = (await db.execute(select(BudgetItem).where(BudgetItem.budget_id == b.id))).scalars().all()
        for item in budget_items:
            allocated += item.amount
            categorized_used += item.used_amount
            items.append({
                "name": item.name if item.name else item.category,
                "category": item.category,
                "budget": item.amount,
                "used": item.used_amount,
                "color": item.color,
                "icon": item.icon,
            })

    unallocated = max(0, total_budget - allocated)
    uncategorized_used = max(0, total_used - categorized_used)

    return {
        "total_budget": total_budget,
        "total_used": total_used,
        "items": items,
        "unallocated": unallocated,
        "uncategorized_used": uncategorized_used,
    }


@router.get("/budgets/{budget_id}/consumption")
async def budget_consumption(
    budget_id: str,
    db: AsyncSession = Depends(get_db),
    user: User = Depends(get_current_user),
    _m: User = Depends(require_module("finance")),
):
    b = (await db.execute(select(Budget).where(Budget.id == budget_id))).scalar_one_or_none()
    if not b:
        raise HTTPException(404, "预算不存在")

    # Expenses by category — direct budget_id match
    exp_conditions = [
        Expense.budget_id == b.id,
        Expense.status.in_(["approved", "paid"]),
    ]
    exp_query = (
        select(Expense.category, func.sum(Expense.amount).label("total"), func.count(Expense.id).label("count"))
        .where(*exp_conditions)
        .group_by(Expense.category)
    )
    exp_rows = (await db.execute(exp_query)).all()
    expenses = [{"category": r.category, "total": float(r.total or 0), "count": r.count} for r in exp_rows]

    # Settlements total — direct budget_id match
    stl_conditions = [
        Settlement.budget_id == b.id,
        Settlement.status.in_(["completed", "settled"]),
    ]
    stl_result = await db.execute(
        select(func.coalesce(func.sum(Settlement.amount), 0.0)).where(*stl_conditions)
    )
    settlement_total = float(stl_result.scalar() or 0)

    # Budget items with their used amounts
    items_result = await db.execute(select(BudgetItem).where(BudgetItem.budget_id == b.id))
    budget_items = items_result.scalars().all()

    # Recent expense items — direct budget_id match
    exp_items = (
        await db.execute(
            select(Expense)
            .where(Expense.budget_id == b.id, Expense.status.in_(["approved", "paid"]))
            .order_by(Expense.updated_at.desc())
            .limit(10)
        )
    ).scalars().all()

    return {
        "expense_breakdown": expenses,
        "settlement_total": settlement_total,
        "items": [_budget_item_row(item) for item in budget_items],
        "recent_expenses": [
            {
                "id": str(e.id),
                "amount": e.amount,
                "category": e.category,
                "description": e.description,
                "date": e.updated_at.isoformat() if e.updated_at else None,
            }
            for e in exp_items
        ],
    }


# ── Dashboard ──

@router.get("/dashboard")
async def finance_dashboard(
    db: AsyncSession = Depends(get_db),
    user: User = Depends(get_current_user),
    _m: User = Depends(require_module("finance")),
):
    dept_cond = (user.department_id is not None and user.role != "admin")

    now = _now()
    # Monthly revenue: payments this calendar month
    month_start = now.replace(day=1, hour=0, minute=0, second=0, microsecond=0)
    month_query = select(func.coalesce(func.sum(Payment.amount), 0.0)).where(
        Payment.payment_date >= month_start
    )
    if dept_cond:
        month_query = month_query.where(Payment.department_id == user.department_id)
    monthly_revenue = (await db.execute(month_query)).scalar() or 0.0

    # Total receivable: invoice amounts - payments for non-paid invoices
    inv_query = select(func.coalesce(func.sum(Invoice.amount), 0.0)).where(
        Invoice.status.in_(["issued", "partial", "draft"])
    )
    if dept_cond:
        inv_query = inv_query.where(Invoice.department_id == user.department_id)
    total_invoiced = (await db.execute(inv_query)).scalar() or 0.0

    paid_query = select(func.coalesce(func.sum(Payment.amount), 0.0))
    if dept_cond:
        paid_query = paid_query.where(Payment.department_id == user.department_id)
    total_paid = (await db.execute(paid_query)).scalar() or 0.0
    total_receivable = max(0, total_invoiced - total_paid)
    collection_rate = round(total_paid / total_invoiced, 4) if total_invoiced > 0 else 0.0

    # Budget usage
    budget_query = select(Budget).where(
        Budget.status == "active",
        Budget.parent_id.is_(None),  # root budgets only — children roll up via propagation
        Budget.year == now.year,
    ).order_by(Budget.total_amount.desc())
    if dept_cond:
        budget_query = budget_query.where(Budget.department_id == user.department_id)
    budgets = (await db.execute(budget_query)).scalars().all()
    budget_usage = [
        {"name": b.name, "total": b.total_amount, "used": b.used_amount}
        for b in budgets
    ]

    # 12-month revenue trend
    import calendar
    from datetime import timedelta
    trend = []
    for i in range(12):
        months_ago = 11 - i
        y = now.year
        m = now.month - months_ago
        while m <= 0:
            m += 12
            y -= 1
        ms = datetime(y, m, 1)
        if m == 12:
            me = datetime(y + 1, 1, 1)
        else:
            me = datetime(y, m + 1, 1)
        month_rev_query = select(func.coalesce(func.sum(Payment.amount), 0.0)).where(
            Payment.payment_date >= ms,
            Payment.payment_date < me,
        )
        if dept_cond:
            month_rev_query = month_rev_query.where(Payment.department_id == user.department_id)
        month_rev = (await db.execute(month_rev_query)).scalar() or 0.0
        trend.append({"month": f"{y}-{m:02d}", "revenue": month_rev})

    # Pending counts
    pending_inv_query = select(func.count(Invoice.id)).where(
        Invoice.status.in_(["draft", "issued", "partial"])
    )
    if dept_cond:
        pending_inv_query = pending_inv_query.where(Invoice.department_id == user.department_id)
    pending_invoices = (await db.execute(pending_inv_query)).scalar() or 0

    pending_pay_query = select(func.count(Invoice.id)).where(
        Invoice.status.in_(["issued", "partial"])
    )
    if dept_cond:
        pending_pay_query = pending_pay_query.where(Invoice.department_id == user.department_id)
    pending_payments = (await db.execute(pending_pay_query)).scalar() or 0

    exp_filter = [Expense.status == "pending"]
    if dept_cond:
        exp_filter.append(Expense.department_id == user.department_id)
    pending_expenses = (await db.execute(
        select(func.count(Expense.id)).where(*exp_filter)
    )).scalar() or 0

    return {
        "monthly_revenue": monthly_revenue,
        "total_receivable": total_receivable,
        "collection_rate": collection_rate,
        "budget_usage": budget_usage,
        "revenue_trend_12m": trend,
        "pending_invoices": pending_invoices,
        "pending_payments": pending_payments,
        "pending_expenses": pending_expenses,
    }
