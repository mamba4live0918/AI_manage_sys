import uuid
from datetime import datetime, timezone

from fastapi import APIRouter, Depends, Form, HTTPException, Request, UploadFile, File as FastAPIFile
from pydantic import BaseModel
from sqlalchemy import select, func
from sqlalchemy.ext.asyncio import AsyncSession

from app.database import get_db
from app.models import User, File, Settlement, Expense, Voucher, Invoice, Payment, Budget
from app.security import get_current_user, require_module
from app.services.audit import log as audit_log
from app.services.storage import upload_file

router = APIRouter(prefix="/finance", tags=["finance"])


def _now():
    return datetime.now(timezone.utc)


async def _check_department(db: AsyncSession, user: User, target_department_id, action: str):
    """非admin用户只能操作本部门数据"""
    if user.role == "admin":
        return
    if target_department_id is not None and user.department_id != target_department_id:
        raise HTTPException(403, f"不能{action}其他部门的财务记录")


# ── Pydantic Schemas ──

class SettlementCreate(BaseModel):
    project_id: str | None = None
    amount: float = 0.0
    status: str = "pending"
    settlement_date: str | None = None
    invoice_no: str = ""
    notes: str = ""


class SettlementUpdate(BaseModel):
    project_id: str | None = None
    amount: float | None = None
    status: str | None = None
    settlement_date: str | None = None
    invoice_no: str | None = None
    notes: str | None = None


class ExpenseCreate(BaseModel):
    project_id: str | None = None
    amount: float = 0.0
    category: str = "other"
    description: str = ""
    submitted_by: str | None = None


class ExpenseApprove(BaseModel):
    status: str  # approved or rejected


class VoucherCreate(BaseModel):
    settlement_id: str | None = None
    expense_id: str | None = None
    type: str = "invoice"
    description: str = ""


class InvoiceCreate(BaseModel):
    project_id: str | None = None
    invoice_no: str = ""
    amount: float = 0.0
    tax_amount: float = 0.0
    tax_rate: float = 0.13
    status: str = "draft"
    issue_date: str | None = None
    due_date: str | None = None
    notes: str = ""

class InvoiceUpdate(BaseModel):
    invoice_no: str | None = None
    amount: float | None = None
    tax_amount: float | None = None
    tax_rate: float | None = None
    status: str | None = None
    issue_date: str | None = None
    due_date: str | None = None
    notes: str | None = None

class PaymentCreate(BaseModel):
    invoice_id: str | None = None
    amount: float = 0.0
    payment_date: str | None = None
    payment_method: str = "bank_transfer"
    ref_no: str = ""
    notes: str = ""


# ── Row Serializers ──

def _settlement_row(s: Settlement) -> dict:
    return {
        "id": str(s.id),
        "project_id": str(s.project_id) if s.project_id else None,
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
        "amount": e.amount,
        "category": e.category,
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
        "invoice_no": inv.invoice_no,
        "amount": inv.amount,
        "tax_amount": inv.tax_amount,
        "tax_rate": inv.tax_rate,
        "status": inv.status,
        "issue_date": inv.issue_date.isoformat() if inv.issue_date else None,
        "due_date": inv.due_date.isoformat() if inv.due_date else None,
        "notes": inv.notes,
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
    settlement_date = datetime.fromisoformat(body.settlement_date) if body.settlement_date else None
    s = Settlement(
        project_id=project_id,
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
    for k, v in body.model_dump(exclude_none=True).items():
        if k == "project_id" and v is not None:
            setattr(s, k, uuid.UUID(v) if v else None)
        elif k == "settlement_date" and v is not None:
            setattr(s, k, datetime.fromisoformat(v) if v else None)
        elif v is not None:
            setattr(s, k, v)
    s.updated_at = _now()
    await db.commit()
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
    await audit_log(db, user, "settlement_delete", "settlement", s.id, s.invoice_no, request=request)
    return {"ok": True}


# ── Expenses ──

@router.get("/expenses")
async def list_expenses(
    category: str = "",
    status: str = "",
    limit: int = 50,
    offset: int = 0,
    db: AsyncSession = Depends(get_db),
    user: User = Depends(get_current_user),
    _m: User = Depends(require_module("finance")),
):
    query = select(Expense).order_by(Expense.updated_at.desc())
    if user.role != "admin":
        if user.department_id:
            query = query.where(Expense.department_id == user.department_id)
        else:
            query = query.where(Expense.submitted_by == user.id)
    if category:
        query = query.where(Expense.category == category)
    if status:
        query = query.where(Expense.status == status)
    result = await db.execute(query.offset(offset).limit(limit))
    return {"items": [_expense_row(e) for e in result.scalars().all()]}


@router.post("/expenses")
async def create_expense(
    body: ExpenseCreate,
    request: Request = None,
    db: AsyncSession = Depends(get_db),
    user: User = Depends(get_current_user),
    _m: User = Depends(require_module("finance")),
):
    project_id = uuid.UUID(body.project_id) if body.project_id else None
    submitted_by = uuid.UUID(body.submitted_by) if body.submitted_by else user.id
    e = Expense(
        project_id=project_id,
        amount=body.amount,
        category=body.category,
        description=body.description,
        submitted_by=submitted_by,
        department_id=user.department_id,
    )
    db.add(e)
    await db.commit()
    await db.refresh(e)
    await audit_log(db, user, "expense_create", "expense", e.id, body.category, request=request)
    return _expense_row(e)


@router.put("/expenses/{expense_id}")
async def approve_expense(
    expense_id: str,
    body: ExpenseApprove,
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
    if body.status not in ("approved", "rejected"):
        raise HTTPException(400, "状态必须是 approved 或 rejected")
    e.status = body.status
    e.updated_at = _now()
    await db.commit()
    await db.refresh(e)
    await audit_log(db, user, f"expense_{body.status}", "expense", e.id, e.category, request=request)
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
    await audit_log(db, user, "expense_delete", "expense", e.id, e.category, request=request)
    return {"ok": True}


# ── Vouchers ──

@router.get("/vouchers")
async def list_vouchers(
    settlement_id: str = "",
    expense_id: str = "",
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
    v = Voucher(
        settlement_id=settlement_id,
        expense_id=expense_id,
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
    v = Voucher(
        settlement_id=sid,
        expense_id=eid,
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
    limit: int = 50,
    offset: int = 0,
    db: AsyncSession = Depends(get_db),
    user: User = Depends(get_current_user),
    _m: User = Depends(require_module("finance")),
):
    query = select(Invoice).order_by(Invoice.updated_at.desc())
    if user.role != "admin":
        if user.department_id:
            query = query.where(Invoice.department_id == user.department_id)
        else:
            query = query.where(Invoice.created_by == user.id)
    if project_id:
        query = query.where(Invoice.project_id == project_id)
    if status:
        query = query.where(Invoice.status == status)
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
    issue_date = datetime.fromisoformat(body.issue_date) if body.issue_date else None
    due_date = datetime.fromisoformat(body.due_date) if body.due_date else None
    i = Invoice(
        project_id=project_id, invoice_no=body.invoice_no, amount=body.amount,
        tax_amount=body.tax_amount, tax_rate=body.tax_rate, status=body.status,
        issue_date=issue_date, due_date=due_date, notes=body.notes,
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
    for k, v in body.model_dump(exclude_unset=True).items():
        if k in ("issue_date", "due_date") and v is not None:
            setattr(i, k, datetime.fromisoformat(v))
        elif v is not None and k not in ("issue_date", "due_date"):
            setattr(i, k, v)
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
    inv_id = p.invoice_id
    await db.delete(p)
    await db.commit()
    if inv_id:
        await _sync_invoice_status(inv_id, db)
    await audit_log(db, user, "payment_delete", "payment", p.id, f"¥{p.amount}", request=request)
    return {"ok": True}
