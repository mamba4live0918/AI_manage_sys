# Finance Module Upgrade Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add invoice/payment tracking, budget management, and a KPI+charts dashboard to the finance module.

**Architecture:** Backend: 3 new SQLAlchemy models (Invoice, Payment, Budget) + CRUD APIs in finance.py + dashboard aggregation endpoint. Frontend: Riverpod providers + rewritten dashboard with fl_chart + new list pages for invoices and budgets. Data flows: dashboard loads on entry + pull-to-refresh + invalidated on create/update/delete.

**Tech Stack:** FastAPI + SQLAlchemy 2.0 async + Flutter Riverpod + fl_chart + Material 3

---

### Task 1: Add Invoice/Payment/Budget models

**Files:**
- Modify: `backend/app/models/models.py` — append after Voucher class

- [ ] **Step 1: Add Invoice, Payment, Budget models to models.py**

```python
class Invoice(Base):
    __tablename__ = "invoices"

    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    project_id: Mapped[uuid.UUID | None] = mapped_column(UUID(as_uuid=True), ForeignKey("pm_projects.id", ondelete="SET NULL"), nullable=True)
    invoice_no: Mapped[str] = mapped_column(String(128), default="")
    amount: Mapped[float] = mapped_column(Float, default=0.0)
    tax_amount: Mapped[float] = mapped_column(Float, default=0.0)
    tax_rate: Mapped[float] = mapped_column(Float, default=0.13)
    status: Mapped[str] = mapped_column(String(32), default="draft")
    issue_date: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)
    due_date: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)
    notes: Mapped[str] = mapped_column(Text, default="")
    department_id: Mapped[uuid.UUID | None] = mapped_column(UUID(as_uuid=True), ForeignKey("departments.id", ondelete="SET NULL"), nullable=True)
    created_by: Mapped[uuid.UUID | None] = mapped_column(UUID(as_uuid=True), ForeignKey("users.id"), nullable=True)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now())
    updated_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now(), onupdate=utcnow)


class Payment(Base):
    __tablename__ = "payments"

    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    invoice_id: Mapped[uuid.UUID | None] = mapped_column(UUID(as_uuid=True), ForeignKey("invoices.id", ondelete="SET NULL"), nullable=True)
    amount: Mapped[float] = mapped_column(Float, default=0.0)
    payment_date: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)
    payment_method: Mapped[str] = mapped_column(String(32), default="bank_transfer")
    ref_no: Mapped[str] = mapped_column(String(128), default="")
    notes: Mapped[str] = mapped_column(Text, default="")
    department_id: Mapped[uuid.UUID | None] = mapped_column(UUID(as_uuid=True), ForeignKey("departments.id", ondelete="SET NULL"), nullable=True)
    created_by: Mapped[uuid.UUID | None] = mapped_column(UUID(as_uuid=True), ForeignKey("users.id"), nullable=True)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now())
    updated_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now(), onupdate=utcnow)


class Budget(Base):
    __tablename__ = "budgets"

    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    department_id: Mapped[uuid.UUID | None] = mapped_column(UUID(as_uuid=True), ForeignKey("departments.id", ondelete="SET NULL"), nullable=True)
    project_id: Mapped[uuid.UUID | None] = mapped_column(UUID(as_uuid=True), ForeignKey("pm_projects.id", ondelete="SET NULL"), nullable=True)
    name: Mapped[str] = mapped_column(String(128), default="")
    year: Mapped[int] = mapped_column(Integer, default=2026)
    quarter: Mapped[int | None] = mapped_column(Integer, nullable=True)
    total_amount: Mapped[float] = mapped_column(Float, default=0.0)
    used_amount: Mapped[float] = mapped_column(Float, default=0.0)
    status: Mapped[str] = mapped_column(String(32), default="active")
    created_by: Mapped[uuid.UUID | None] = mapped_column(UUID(as_uuid=True), ForeignKey("users.id"), nullable=True)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now())
    updated_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now(), onupdate=utcnow)
```

Also add `invoice_id` to Settlement model (add after `project_id`):
```python
    invoice_id: Mapped[uuid.UUID | None] = mapped_column(UUID(as_uuid=True), ForeignKey("invoices.id", ondelete="SET NULL"), nullable=True)
```

- [ ] **Step 2: Commit**

```bash
git add backend/app/models/models.py
git commit -m "feat: add Invoice, Payment, Budget models + Settlement.invoice_id"
```

---

### Task 2: Add Invoice/Payment CRUD to finance API

**Files:**
- Modify: `backend/app/api/finance.py` — append after voucher delete endpoint

- [ ] **Step 1: Add Pydantic models**

```python
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
```

- [ ] **Step 2: Add row helper functions**

```python
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
```

- [ ] **Step 3: Add Invoice CRUD endpoints**

```python
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
```

- [ ] **Step 4: Add Payment CRUD with auto-status**

```python
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
        else:
            inv.status = "issued" if inv.status == "paid" else inv.status
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
```

- [ ] **Step 5: Add imports**

At top of finance.py, ensure these imports exist:
```python
from app.models import User, File, Settlement, Expense, Voucher, Invoice, Payment, Budget
from sqlalchemy import func
```

- [ ] **Step 6: Commit**

```bash
git add backend/app/api/finance.py
git commit -m "feat: add Invoice and Payment CRUD with auto status sync"
```

---

### Task 3: Add Budget CRUD + used_amount + dashboard API

**Files:**
- Modify: `backend/app/api/finance.py` — append after Payment endpoints

- [ ] **Step 1: Add Budget Pydantic models**

```python
class BudgetCreate(BaseModel):
    department_id: str | None = None
    project_id: str | None = None
    name: str = ""
    year: int = 2026
    quarter: int | None = None
    total_amount: float = 0.0
    status: str = "active"

class BudgetUpdate(BaseModel):
    name: str | None = None
    year: int | None = None
    quarter: int | None = None
    total_amount: float | None = None
    status: str | None = None
```

- [ ] **Step 2: Add _budget_row helper + used_amount calculation**

```python
def _budget_row(b: Budget) -> dict:
    return {
        "id": str(b.id),
        "department_id": str(b.department_id) if b.department_id else None,
        "project_id": str(b.project_id) if b.project_id else None,
        "name": b.name,
        "year": b.year,
        "quarter": b.quarter,
        "total_amount": b.total_amount,
        "used_amount": b.used_amount,
        "status": b.status,
        "created_at": b.created_at.isoformat() if b.created_at else None,
    }

async def _recalc_budget_usage(db: AsyncSession):
    """Recalculate used_amount for all active budgets."""
    budgets = (await db.execute(select(Budget).where(Budget.status == "active"))).scalars().all()
    for b in budgets:
        conditions = [Expense.department_id == b.department_id, Expense.status == "approved"]
        if b.project_id:
            conditions.append(Expense.project_id == b.project_id)
        exp_result = await db.execute(
            select(func.coalesce(func.sum(Expense.amount), 0.0)).where(*conditions)
        )
        expense_total = exp_result.scalar() or 0.0

        stl_conditions = [Settlement.department_id == b.department_id, Settlement.status.in_(["completed", "settled"])]
        if b.project_id:
            stl_conditions.append(Settlement.project_id == b.project_id)
        stl_result = await db.execute(
            select(func.coalesce(func.sum(Settlement.amount), 0.0)).where(*stl_conditions)
        )
        settlement_total = stl_result.scalar() or 0.0

        b.used_amount = expense_total + settlement_total
    await db.commit()
```

- [ ] **Step 3: Add Budget CRUD endpoints**

```python
# ── Budgets ──

@router.get("/budgets")
async def list_budgets(
    department_id: str = "",
    year: int = 0,
    db: AsyncSession = Depends(get_db),
    user: User = Depends(get_current_user),
    _m: User = Depends(require_module("finance")),
):
    query = select(Budget).order_by(Budget.updated_at.desc())
    if user.role != "admin":
        if user.department_id:
            query = query.where(Budget.department_id == user.department_id)
    if department_id:
        query = query.where(Budget.department_id == department_id)
    if year:
        query = query.where(Budget.year == year)
    result = await db.execute(query)
    return {"items": [_budget_row(b) for b in result.scalars().all()]}


@router.post("/budgets")
async def create_budget(
    body: BudgetCreate,
    request: Request = None,
    db: AsyncSession = Depends(get_db),
    user: User = Depends(get_current_user),
    _m: User = Depends(require_module("finance")),
):
    dept_id = uuid.UUID(body.department_id) if body.department_id else user.department_id
    project_id = uuid.UUID(body.project_id) if body.project_id else None

    # Validate: project budget must not exceed department budget
    if project_id:
        dept_budget = (await db.execute(
            select(func.coalesce(func.sum(Budget.total_amount), 0.0)).where(
                Budget.department_id == dept_id,
                Budget.project_id.is_(None),
                Budget.status == "active",
                Budget.year == body.year,
            )
        )).scalar() or 0.0
        proj_budgets = (await db.execute(
            select(func.coalesce(func.sum(Budget.total_amount), 0.0)).where(
                Budget.department_id == dept_id,
                Budget.project_id.isnot(None),
                Budget.status == "active",
                Budget.year == body.year,
            )
        )).scalar() or 0.0
        if proj_budgets + body.total_amount > dept_budget:
            raise HTTPException(400, f"项目预算总和({proj_budgets + body.total_amount:.0f})超过部门预算({dept_budget:.0f})")

    b = Budget(
        department_id=dept_id, project_id=project_id, name=body.name,
        year=body.year, quarter=body.quarter, total_amount=body.total_amount,
        status=body.status, created_by=user.id,
    )
    db.add(b)
    await db.commit()
    await db.refresh(b)
    await audit_log(db, user, "budget_create", "budget", b.id, b.name, request=request)
    return _budget_row(b)


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
    for k, v in body.model_dump(exclude_unset=True).items():
        if v is not None:
            setattr(b, k, v)
    await db.commit()
    await db.refresh(b)
    await audit_log(db, user, "budget_update", "budget", b.id, b.name, request=request)
    return _budget_row(b)


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
    await db.delete(b)
    await db.commit()
    await audit_log(db, user, "budget_delete", "budget", b.id, b.name, request=request)
    return {"ok": True}
```

- [ ] **Step 4: Add dashboard endpoint**

```python
# ── Dashboard ──

@router.get("/dashboard")
async def finance_dashboard(
    db: AsyncSession = Depends(get_db),
    user: User = Depends(get_current_user),
    _m: User = Depends(require_module("finance")),
):
    dept_filter = [Payment.department_id == user.department_id] if user.role != "admin" and user.department_id else []

    # Monthly revenue (this month payments)
    now = datetime.utcnow()
    month_start = now.replace(day=1, hour=0, minute=0, second=0, microsecond=0)
    month_result = await db.execute(
        select(func.coalesce(func.sum(Payment.amount), 0.0)).where(
            Payment.payment_date >= month_start, *dept_filter
        )
    )
    monthly_revenue = month_result.scalar() or 0.0

    # Total receivable: unpaid invoice amounts minus partial payments
    inv_result = await db.execute(
        select(func.coalesce(func.sum(Invoice.amount), 0.0)).where(
            Invoice.status.in_(["issued", "partial", "draft"]), *dept_filter
        )
    )
    total_invoiced = inv_result.scalar() or 0.0
    paid_result = await db.execute(
        select(func.coalesce(func.sum(Payment.amount), 0.0)).where(*dept_filter)
    )
    total_paid = paid_result.scalar() or 0.0
    total_receivable = max(0, total_invoiced - total_paid)
    collection_rate = total_paid / total_invoiced if total_invoiced > 0 else 0.0

    # Budget usage
    budget_query = select(Budget).where(Budget.status == "active").order_by(Budget.total_amount.desc())
    if user.role != "admin" and user.department_id:
        budget_query = budget_query.where(Budget.department_id == user.department_id)
    budgets = (await db.execute(budget_query)).scalars().all()
    budget_usage = [
        {"name": b.name, "total": b.total_amount, "used": b.used_amount}
        for b in budgets
    ]

    # 12-month revenue trend
    trend = []
    for i in range(11, -1, -1):
        m = (now.month - 1 - i) % 12 + 1
        y = now.year - (1 if now.month - 1 - i < 0 else 0) - (1 if now.month - 1 - i < -12 else 0)
        if i >= 12:
            continue
        # Fix year calculation
        months_ago = now.month - 1 - i
        if months_ago >= 0:
            y = now.year
            m = months_ago + 1
        else:
            y = now.year - 1 + (months_ago // 12)
            m = (months_ago % 12) + 1
        ms = datetime(y, m, 1)
        me = (datetime(y, m, 1) + __import__('calendar').__getattr__('monthrange')(y, m)[1]).replace(day=1) if m < 12 else datetime(y + 1, 1, 1)
        next_month = ms.replace(day=28) + __import__('datetime').timedelta(days=4)
        me = next_month.replace(day=1)
        month_rev = (await db.execute(
            select(func.coalesce(func.sum(Payment.amount), 0.0)).where(
                Payment.payment_date >= ms,
                Payment.payment_date < me,
                *dept_filter,
            )
        )).scalar() or 0.0
        trend.append({"month": f"{y}-{m:02d}", "revenue": month_rev})

    # Pending counts
    pending_invoices = (await db.execute(
        select(func.count(Invoice.id)).where(Invoice.status.in_(["draft", "issued", "partial"]), *dept_filter)
    )).scalar() or 0
    pending_payments = (await db.execute(
        select(func.count(Invoice.id)).where(Invoice.status.in_(["issued", "partial"]), *dept_filter)
    )).scalar() or 0

    exp_filter = [Expense.status == "pending"]
    if user.role != "admin" and user.department_id:
        exp_filter.append(Expense.department_id == user.department_id)
    pending_expenses = (await db.execute(
        select(func.count(Expense.id)).where(*exp_filter)
    )).scalar() or 0

    return {
        "monthly_revenue": monthly_revenue,
        "total_receivable": total_receivable,
        "collection_rate": round(collection_rate, 4),
        "budget_usage": budget_usage,
        "revenue_trend_12m": trend,
        "pending_invoices": pending_invoices,
        "pending_payments": pending_payments,
        "pending_expenses": pending_expenses,
    }
```

- [ ] **Step 5: Commit**

```bash
git add backend/app/api/finance.py
git commit -m "feat: add Budget CRUD, used_amount calc, and dashboard API"
```

---

### Task 4: Add Flutter data models for Invoice/Payment/Budget/Dashboard

**Files:**
- Create: `frontend/lib/models/finance_models.dart`

- [ ] **Step 1: Create finance_models.dart**

```dart
class InvoiceData {
  final String id;
  final String? projectId;
  final String invoiceNo;
  final double amount;
  final double taxAmount;
  final double taxRate;
  final String status;
  final String? issueDate;
  final String? dueDate;
  final String notes;
  final String? createdAt;

  InvoiceData({required this.id, this.projectId, required this.invoiceNo,
    required this.amount, required this.taxAmount, required this.taxRate,
    required this.status, this.issueDate, this.dueDate, required this.notes,
    this.createdAt});

  factory InvoiceData.fromJson(Map<String, dynamic> json) => InvoiceData(
    id: json['id'] ?? '',
    projectId: json['project_id'],
    invoiceNo: json['invoice_no'] ?? '',
    amount: (json['amount'] ?? 0).toDouble(),
    taxAmount: (json['tax_amount'] ?? 0).toDouble(),
    taxRate: (json['tax_rate'] ?? 0.13).toDouble(),
    status: json['status'] ?? 'draft',
    issueDate: json['issue_date'],
    dueDate: json['due_date'],
    notes: json['notes'] ?? '',
    createdAt: json['created_at'],
  );
}

class PaymentData {
  final String id;
  final String? invoiceId;
  final double amount;
  final String? paymentDate;
  final String paymentMethod;
  final String refNo;
  final String notes;

  PaymentData({required this.id, this.invoiceId, required this.amount,
    this.paymentDate, required this.paymentMethod, required this.refNo,
    required this.notes});

  factory PaymentData.fromJson(Map<String, dynamic> json) => PaymentData(
    id: json['id'] ?? '',
    invoiceId: json['invoice_id'],
    amount: (json['amount'] ?? 0).toDouble(),
    paymentDate: json['payment_date'],
    paymentMethod: json['payment_method'] ?? 'bank_transfer',
    refNo: json['ref_no'] ?? '',
    notes: json['notes'] ?? '',
  );
}

class BudgetData {
  final String id;
  final String? departmentId;
  final String? projectId;
  final String name;
  final int year;
  final int? quarter;
  final double totalAmount;
  final double usedAmount;
  final String status;

  BudgetData({required this.id, this.departmentId, this.projectId,
    required this.name, required this.year, this.quarter,
    required this.totalAmount, required this.usedAmount, required this.status});

  factory BudgetData.fromJson(Map<String, dynamic> json) => BudgetData(
    id: json['id'] ?? '',
    departmentId: json['department_id'],
    projectId: json['project_id'],
    name: json['name'] ?? '',
    year: json['year'] ?? 2026,
    quarter: json['quarter'],
    totalAmount: (json['total_amount'] ?? 0).toDouble(),
    usedAmount: (json['used_amount'] ?? 0).toDouble(),
    status: json['status'] ?? 'active',
  );
}

class FinanceDashboardData {
  final double monthlyRevenue;
  final double totalReceivable;
  final double collectionRate;
  final List<BudgetUsage> budgetUsage;
  final List<RevenueTrend> revenueTrend12m;
  final int pendingInvoices;
  final int pendingPayments;
  final int pendingExpenses;

  FinanceDashboardData({required this.monthlyRevenue, required this.totalReceivable,
    required this.collectionRate, required this.budgetUsage, required this.revenueTrend12m,
    required this.pendingInvoices, required this.pendingPayments, required this.pendingExpenses});

  factory FinanceDashboardData.fromJson(Map<String, dynamic> json) => FinanceDashboardData(
    monthlyRevenue: (json['monthly_revenue'] ?? 0).toDouble(),
    totalReceivable: (json['total_receivable'] ?? 0).toDouble(),
    collectionRate: (json['collection_rate'] ?? 0).toDouble(),
    budgetUsage: (json['budget_usage'] as List? ?? []).map((b) => BudgetUsage.fromJson(b)).toList(),
    revenueTrend12m: (json['revenue_trend_12m'] as List? ?? []).map((t) => RevenueTrend.fromJson(t)).toList(),
    pendingInvoices: json['pending_invoices'] ?? 0,
    pendingPayments: json['pending_payments'] ?? 0,
    pendingExpenses: json['pending_expenses'] ?? 0,
  );
}

class BudgetUsage {
  final String name;
  final double total;
  final double used;
  BudgetUsage({required this.name, required this.total, required this.used});
  factory BudgetUsage.fromJson(Map<String, dynamic> json) => BudgetUsage(
    name: json['name'] ?? '', total: (json['total'] ?? 0).toDouble(), used: (json['used'] ?? 0).toDouble());
}

class RevenueTrend {
  final String month;
  final double revenue;
  RevenueTrend({required this.month, required this.revenue});
  factory RevenueTrend.fromJson(Map<String, dynamic> json) => RevenueTrend(
    month: json['month'] ?? '', revenue: (json['revenue'] ?? 0).toDouble());
}
```

- [ ] **Step 2: Commit**

```bash
git add frontend/lib/models/finance_models.dart
git commit -m "feat: add Flutter models for Invoice, Payment, Budget, Dashboard"
```

---

### Task 5: Add Flutter Riverpod providers for finance

**Files:**
- Create: `frontend/lib/providers/finance_providers.dart`

- [ ] **Step 1: Create providers file**

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/finance_models.dart';
import '../services/api_client.dart';

class FinanceDashboardState {
  final FinanceDashboardData? data;
  final bool loading;
  final String? error;
  const FinanceDashboardState({this.data, this.loading = false, this.error});
}

class FinanceDashboardNotifier extends StateNotifier<FinanceDashboardState> {
  FinanceDashboardNotifier() : super(const FinanceDashboardState());

  Future<void> load() async {
    state = const FinanceDashboardState(loading: true);
    try {
      final resp = await apiClient.get('/api/finance/dashboard');
      state = FinanceDashboardState(data: FinanceDashboardData.fromJson(resp.data));
    } catch (e) {
      state = FinanceDashboardState(error: e.toString());
    }
  }
}

final financeDashboardProvider = StateNotifierProvider<FinanceDashboardNotifier, FinanceDashboardState>(
  (ref) => FinanceDashboardNotifier(),
);

// Invoices
class FinanceInvoiceState {
  final List<InvoiceData> items;
  final bool loading;
  const FinanceInvoiceState({this.items = const [], this.loading = false});
}

class FinanceInvoiceNotifier extends StateNotifier<FinanceInvoiceState> {
  FinanceInvoiceNotifier() : super(const FinanceInvoiceState());

  Future<void> load({String projectId = '', String status = ''}) async {
    state = const FinanceInvoiceState(loading: true);
    try {
      final params = <String, String>{};
      if (projectId.isNotEmpty) params['project_id'] = projectId;
      if (status.isNotEmpty) params['status'] = status;
      final resp = await apiClient.get('/api/finance/invoices', queryParameters: params.isNotEmpty ? params : null);
      final items = (resp.data['items'] as List).map((j) => InvoiceData.fromJson(j)).toList();
      state = FinanceInvoiceState(items: items);
    } catch (e) {
      state = const FinanceInvoiceState();
    }
  }
}

final financeInvoiceProvider = StateNotifierProvider<FinanceInvoiceNotifier, FinanceInvoiceState>(
  (ref) => FinanceInvoiceNotifier(),
);

// Budgets
class FinanceBudgetState {
  final List<BudgetData> items;
  final bool loading;
  const FinanceBudgetState({this.items = const [], this.loading = false});
}

class FinanceBudgetNotifier extends StateNotifier<FinanceBudgetState> {
  FinanceBudgetNotifier() : super(const FinanceBudgetState());

  Future<void> load() async {
    state = const FinanceBudgetState(loading: true);
    try {
      final resp = await apiClient.get('/api/finance/budgets');
      final items = (resp.data['items'] as List).map((j) => BudgetData.fromJson(j)).toList();
      state = FinanceBudgetState(items: items);
    } catch (e) {
      state = const FinanceBudgetState();
    }
  }
}

final financeBudgetProvider = StateNotifierProvider<FinanceBudgetNotifier, FinanceBudgetState>(
  (ref) => FinanceBudgetNotifier(),
);
```

- [ ] **Step 2: Commit**

```bash
git add frontend/lib/providers/finance_providers.dart
git commit -m "feat: add finance Riverpod providers"
```

---

### Task 6: Rewrite finance dashboard page with KPI + charts

**Files:**
- Modify: `frontend/lib/pages/finance/finance_dashboard_page.dart` — full rewrite

- [ ] **Step 1: Rewrite dashboard page**

Replace the TabBar-based page with a charts+KPI dashboard (same pattern as HR dashboard). Key sections:

1. **KPI cards row**: 本月收入 / 累计应收 / 回款率 / 待处理
2. **Revenue trend line chart**: 12-month revenue using fl_chart LineChart
3. **Budget usage bars**: Progress bars per budget item
4. **Quick actions**: 发票管理 / 收款管理 / 预算管理 → state-based navigation (no Navigator)

Use `FinanceDashboardPage` as `ConsumerStatefulWidget` with `_activeView` state (same pattern as HR dashboard).

- [ ] Full implementation will be executed by the subagent — see spec for widget layout details.

- [ ] **Step 2: Commit**

```bash
git add frontend/lib/pages/finance/finance_dashboard_page.dart
git commit -m "feat: rewrite finance dashboard with KPI cards, charts, quick actions"
```

---

### Task 7: Add invoice list + budget pages (Flutter)

**Files:**
- Create: `frontend/lib/pages/finance/finance_invoice_page.dart`
- Create: `frontend/lib/pages/finance/finance_budget_page.dart`

- [ ] **Step 1: Create invoice list/create page**

`FinanceInvoicePage` — Scaffold with AppBar, list of invoices with status chips (draft/issued/paid/partial), FAB for create. Create dialog with fields: project selector, invoice_no, amount, tax_amount, issue_date, due_date, notes.

- [ ] **Step 2: Create budget list/create page**

`FinanceBudgetPage` — Scaffold with AppBar, list of budgets with progress bars (used/total), FAB for create. Create dialog with fields: name, year, quarter, total_amount, project_id (optional), department_id.

Both pages accept `VoidCallback? onBack` for use with state-based navigation.

- [ ] **Step 3: Commit**

```bash
git add frontend/lib/pages/finance/finance_invoice_page.dart frontend/lib/pages/finance/finance_budget_page.dart
git commit -m "feat: add invoice list and budget management pages"
```
