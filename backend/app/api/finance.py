import uuid
from datetime import datetime, timezone

from fastapi import APIRouter, Depends, Form, HTTPException, Request, UploadFile, File as FastAPIFile
from pydantic import BaseModel
from sqlalchemy import select, func
from sqlalchemy.ext.asyncio import AsyncSession

from app.database import get_db
from app.models import User, File, Settlement, Expense, Voucher
from app.security import get_current_user
from app.services.audit import log as audit_log
from app.services.storage import upload_file

router = APIRouter(prefix="/finance", tags=["finance"])


def _now():
    return datetime.now(timezone.utc)


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
    type: str = "invoice"
    description: str = ""


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
        "file_id": str(v.file_id) if v.file_id else None,
        "type": v.type,
        "description": v.description,
        "department_id": str(v.department_id) if v.department_id else None,
        "created_by": str(v.created_by) if v.created_by else None,
        "created_at": v.created_at.isoformat() if v.created_at else None,
    }


# ── Settlements ──

@router.get("/settlements")
async def list_settlements(
    status: str = "",
    limit: int = 50,
    offset: int = 0,
    db: AsyncSession = Depends(get_db),
    user: User = Depends(get_current_user),
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
):
    result = await db.execute(select(Settlement).where(Settlement.id == settlement_id))
    s = result.scalar_one_or_none()
    if not s:
        raise HTTPException(404, "结算不存在")
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
):
    result = await db.execute(select(Settlement).where(Settlement.id == settlement_id))
    s = result.scalar_one_or_none()
    if not s:
        raise HTTPException(404, "结算不存在")
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
):
    result = await db.execute(select(Expense).where(Expense.id == expense_id))
    e = result.scalar_one_or_none()
    if not e:
        raise HTTPException(404, "报销不存在")
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
):
    result = await db.execute(select(Expense).where(Expense.id == expense_id))
    e = result.scalar_one_or_none()
    if not e:
        raise HTTPException(404, "报销不存在")
    await db.delete(e)
    await db.commit()
    await audit_log(db, user, "expense_delete", "expense", e.id, e.category, request=request)
    return {"ok": True}


# ── Vouchers ──

@router.get("/vouchers")
async def list_vouchers(
    settlement_id: str = "",
    limit: int = 50,
    offset: int = 0,
    db: AsyncSession = Depends(get_db),
    user: User = Depends(get_current_user),
):
    query = select(Voucher).order_by(Voucher.created_at.desc())
    if user.role != "admin":
        if user.department_id:
            query = query.where(Voucher.department_id == user.department_id)
        else:
            query = query.where(Voucher.created_by == user.id)
    if settlement_id:
        query = query.where(Voucher.settlement_id == settlement_id)
    result = await db.execute(query.offset(offset).limit(limit))
    return {"items": [_voucher_row(v) for v in result.scalars().all()]}


@router.post("/vouchers")
async def create_voucher(
    body: VoucherCreate,
    request: Request = None,
    db: AsyncSession = Depends(get_db),
    user: User = Depends(get_current_user),
):
    settlement_id = uuid.UUID(body.settlement_id) if body.settlement_id else None
    v = Voucher(
        settlement_id=settlement_id,
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
    request: Request = None,
    db: AsyncSession = Depends(get_db),
    user: User = Depends(get_current_user),
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
    v = Voucher(
        settlement_id=sid,
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
):
    result = await db.execute(select(Voucher).where(Voucher.id == voucher_id))
    v = result.scalar_one_or_none()
    if not v:
        raise HTTPException(404, "凭证不存在")
    await db.delete(v)
    await db.commit()
    await audit_log(db, user, "voucher_delete", "voucher", v.id, v.description, request=request)
    return {"ok": True}
