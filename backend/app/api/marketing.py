import re
import uuid
from datetime import datetime, timezone, timedelta
from fastapi import APIRouter, Depends, HTTPException, Request, UploadFile, File as FastAPIFile
from pydantic import BaseModel
from sqlalchemy import select, func
from sqlalchemy.ext.asyncio import AsyncSession
from app.database import get_db
from app.models import (
    User, Customer, CustomerBehavior, CustomerSatisfaction,
    ChurnConfig, ChurnWarning, MarketingProposal,
    MarketingProject, ProjectBrief, CommunityInteraction,
    CommunityDailyStat, KnowledgeEntry, QAChatRecord, File,
)
from app.security import get_current_user
from app.services.llm.router import get_llm
from app.services.llm.base import LLMConfig
from app.services.file_extractor import extract_text
from app.services.storage import upload_file, get_presigned_url, delete_file
from app.services.audit import log as audit_log

router = APIRouter(prefix="/marketing", tags=["marketing"])


def _now():
    return datetime.now(timezone.utc)


def _dept_filter(user: User):
    """Return a WHERE clause that isolates non-admin users to their department."""
    if user.role == "admin":
        return True
    if user.department_id:
        return Customer.department_id == user.department_id
    return Customer.created_by == user.id


# ── Pydantic Schemas ──

class CustomerCreate(BaseModel):
    name: str
    industry: str = ""
    contact_person: str = ""
    contact_phone: str = ""
    contact_email: str = ""
    source: str = ""
    status: str = "active"
    tags: list[str] = []
    notes: str = ""


class CustomerUpdate(BaseModel):
    name: str | None = None
    industry: str | None = None
    contact_person: str | None = None
    contact_phone: str | None = None
    contact_email: str | None = None
    source: str | None = None
    status: str | None = None
    tags: list[str] | None = None
    notes: str | None = None


class BehaviorCreate(BaseModel):
    event_type: str
    description: str = ""
    event_date: str | None = None  # ISO datetime string


class SatisfactionCreate(BaseModel):
    score: int
    comment: str = ""
    survey_date: str | None = None


class ChurnConfigUpdate(BaseModel):
    inactivity_days: int | None = None
    low_satisfaction_threshold: int | None = None
    auto_notify: bool | None = None
    notify_emails: list[str] | None = None


class ProposalGenerateRequest(BaseModel):
    customer_id: str | None = None
    title: str
    topic: str = ""
    requirements: str = ""
    additional_info: str = ""


class ProposalUpdate(BaseModel):
    title: str | None = None
    content: str | None = None
    status: str | None = None


class ProjectCreate(BaseModel):
    customer_id: str | None = None
    name: str
    stage: str = "initial_contact"
    data_sources: list[dict] = []


class ProjectUpdate(BaseModel):
    name: str | None = None
    stage: str | None = None
    data_sources: list[dict] | None = None


class BriefGenerateRequest(BaseModel):
    additional_info: str = ""


class InteractionCreate(BaseModel):
    platform: str = "wechat_group"
    group_name: str = ""
    user_name: str = ""
    content: str
    tags: list[str] = []
    interaction_date: str | None = None


class DailyStatCreate(BaseModel):
    date: str
    platform: str = "wechat_group"
    group_name: str = ""
    total_members: int = 0
    active_users: int = 0
    message_count: int = 0
    new_members: int = 0


class KnowledgeEntryCreate(BaseModel):
    title: str
    content: str = ""
    category: str = ""
    tags: list[str] = []


class KnowledgeEntryUpdate(BaseModel):
    title: str | None = None
    content: str | None = None
    category: str | None = None
    tags: list[str] | None = None


class KnowledgeQARequest(BaseModel):
    question: str
    top_k: int = 5
    history: list[dict] = []  # [{role: "user"|"assistant", content: "..."}]


# ── Helpers ──

def _customer_row(c: Customer) -> dict:
    return {
        "id": str(c.id),
        "name": c.name,
        "industry": c.industry,
        "contact_person": c.contact_person,
        "contact_phone": c.contact_phone,
        "contact_email": c.contact_email,
        "source": c.source,
        "status": c.status,
        "tags": c.tags,
        "notes": c.notes,
        "department_id": str(c.department_id) if c.department_id else None,
        "created_by": str(c.created_by) if c.created_by else None,
        "created_at": c.created_at.isoformat() if c.created_at else None,
        "updated_at": c.updated_at.isoformat() if c.updated_at else None,
    }


# ── Customer CRUD ──

@router.get("/customers")
async def list_customers(
    search: str = "",
    status: str = "",
    limit: int = 50,
    offset: int = 0,
    db: AsyncSession = Depends(get_db),
    user: User = Depends(get_current_user),
):
    query = select(Customer).order_by(Customer.updated_at.desc())
    if user.role != "admin":
        if user.department_id:
            query = query.where(Customer.department_id == user.department_id)
        else:
            query = query.where(Customer.created_by == user.id)
    if search:
        query = query.where(
            Customer.name.ilike(f"%{search}%")
            | Customer.industry.ilike(f"%{search}%")
        )
    if status:
        query = query.where(Customer.status == status)
    result = await db.execute(query.offset(offset).limit(limit))
    rows = result.scalars().all()
    return {"items": [_customer_row(c) for c in rows], "total": len(rows)}


@router.post("/customers")
async def create_customer(
    body: CustomerCreate,
    request: Request = None,
    db: AsyncSession = Depends(get_db),
    user: User = Depends(get_current_user),
):
    c = Customer(
        name=body.name,
        industry=body.industry,
        contact_person=body.contact_person,
        contact_phone=body.contact_phone,
        contact_email=body.contact_email,
        source=body.source,
        status=body.status,
        tags=body.tags,
        notes=body.notes,
        department_id=user.department_id,
        created_by=user.id,
    )
    db.add(c)
    await db.commit()
    await db.refresh(c)
    await audit_log(db, user, "customer_create", "customer", c.id, c.name, "success", request=request)
    return _customer_row(c)


@router.get("/customers/{customer_id}")
async def get_customer(
    customer_id: str,
    db: AsyncSession = Depends(get_db),
    user: User = Depends(get_current_user),
):
    c = await _get_customer(customer_id, db, user)
    return _customer_row(c)


@router.put("/customers/{customer_id}")
async def update_customer(
    customer_id: str,
    body: CustomerUpdate,
    request: Request = None,
    db: AsyncSession = Depends(get_db),
    user: User = Depends(get_current_user),
):
    c = await _get_customer(customer_id, db, user)
    for field, val in body.model_dump(exclude_unset=True).items():
        setattr(c, field, val)
    await db.commit()
    await db.refresh(c)
    await audit_log(db, user, "customer_update", "customer", c.id, c.name, "success", request=request)
    return _customer_row(c)


@router.delete("/customers/{customer_id}")
async def delete_customer(
    customer_id: str,
    request: Request = None,
    db: AsyncSession = Depends(get_db),
    user: User = Depends(get_current_user),
):
    c = await _get_customer(customer_id, db, user)
    await db.delete(c)
    await db.commit()
    await audit_log(db, user, "customer_delete", "customer", c.id, c.name, "success", request=request)
    return {"message": "已删除"}


async def _get_customer(customer_id: str, db: AsyncSession, user: User) -> Customer:
    result = await db.execute(
        select(Customer).where(Customer.id == uuid.UUID(customer_id))
    )
    c = result.scalar_one_or_none()
    if not c:
        raise HTTPException(status_code=404, detail="客户不存在")
    if user.role != "admin" and user.department_id and c.department_id != user.department_id:
        raise HTTPException(status_code=403, detail="无权访问")
    return c


# ── Behavior Events ──

@router.get("/customers/{customer_id}/behaviors")
async def list_behaviors(
    customer_id: str,
    limit: int = 50,
    offset: int = 0,
    db: AsyncSession = Depends(get_db),
    user: User = Depends(get_current_user),
):
    await _get_customer(customer_id, db, user)
    result = await db.execute(
        select(CustomerBehavior)
        .where(CustomerBehavior.customer_id == uuid.UUID(customer_id))
        .order_by(CustomerBehavior.event_date.desc())
        .offset(offset).limit(limit)
    )
    rows = result.scalars().all()
    return {
        "items": [
            {
                "id": str(r.id),
                "customer_id": str(r.customer_id),
                "event_type": r.event_type,
                "description": r.description,
                "event_date": r.event_date.isoformat() if r.event_date else None,
                "recorded_by": str(r.recorded_by) if r.recorded_by else None,
                "created_at": r.created_at.isoformat() if r.created_at else None,
            }
            for r in rows
        ]
    }


@router.post("/customers/{customer_id}/behaviors")
async def record_behavior(
    customer_id: str,
    body: BehaviorCreate,
    request: Request = None,
    db: AsyncSession = Depends(get_db),
    user: User = Depends(get_current_user),
):
    await _get_customer(customer_id, db, user)
    event_date = datetime.fromisoformat(body.event_date) if body.event_date else _now()
    b = CustomerBehavior(
        customer_id=uuid.UUID(customer_id),
        event_type=body.event_type,
        description=body.description,
        event_date=event_date,
        recorded_by=user.id,
    )
    db.add(b)
    await db.commit()
    await db.refresh(b)
    await audit_log(db, user, "behavior_record", "customer_behavior", b.id, body.event_type, "success", request=request)
    return {"id": str(b.id), "event_type": b.event_type, "event_date": b.event_date.isoformat()}


# ── Satisfaction ──

@router.get("/customers/{customer_id}/satisfactions")
async def list_satisfactions(
    customer_id: str,
    limit: int = 50,
    offset: int = 0,
    db: AsyncSession = Depends(get_db),
    user: User = Depends(get_current_user),
):
    await _get_customer(customer_id, db, user)
    result = await db.execute(
        select(CustomerSatisfaction)
        .where(CustomerSatisfaction.customer_id == uuid.UUID(customer_id))
        .order_by(CustomerSatisfaction.survey_date.desc())
        .offset(offset).limit(limit)
    )
    rows = result.scalars().all()
    return {
        "items": [
            {
                "id": str(r.id),
                "customer_id": str(r.customer_id),
                "score": r.score,
                "comment": r.comment,
                "survey_date": r.survey_date.isoformat() if r.survey_date else None,
                "created_at": r.created_at.isoformat() if r.created_at else None,
            }
            for r in rows
        ]
    }


@router.post("/customers/{customer_id}/satisfactions")
async def record_satisfaction(
    customer_id: str,
    body: SatisfactionCreate,
    request: Request = None,
    db: AsyncSession = Depends(get_db),
    user: User = Depends(get_current_user),
):
    await _get_customer(customer_id, db, user)
    survey_date = datetime.fromisoformat(body.survey_date) if body.survey_date else _now()
    s = CustomerSatisfaction(
        customer_id=uuid.UUID(customer_id),
        score=body.score,
        comment=body.comment,
        survey_date=survey_date,
        recorded_by=user.id,
    )
    db.add(s)
    await db.commit()
    await db.refresh(s)
    await audit_log(db, user, "satisfaction_record", "customer_satisfaction", s.id, str(s.score), "success", request=request)
    return {"id": str(s.id), "score": s.score}


@router.get("/customers/{customer_id}/satisfaction-trend")
async def satisfaction_trend(
    customer_id: str,
    db: AsyncSession = Depends(get_db),
    user: User = Depends(get_current_user),
):
    await _get_customer(customer_id, db, user)
    twelve_months_ago = _now().replace(year=_now().year - 1)
    result = await db.execute(
        select(
            func.date_trunc("month", CustomerSatisfaction.survey_date).label("month"),
            func.avg(CustomerSatisfaction.score).label("avg_score"),
            func.count(CustomerSatisfaction.id).label("count"),
        )
        .where(CustomerSatisfaction.customer_id == uuid.UUID(customer_id))
        .where(CustomerSatisfaction.survey_date >= twelve_months_ago)
        .group_by("month")
        .order_by("month")
    )
    rows = result.all()
    return {
        "trend": [
            {"month": r.month.strftime("%Y-%m") if r.month else "", "avg_score": round(float(r.avg_score), 1), "count": r.count}
            for r in rows
        ]
    }


# ── Churn Warning ──

@router.get("/churn-config")
async def get_churn_config(
    db: AsyncSession = Depends(get_db),
    user: User = Depends(get_current_user),
):
    result = await db.execute(
        select(ChurnConfig).where(ChurnConfig.department_id == user.department_id)
    )
    config = result.scalar_one_or_none()
    if not config:
        config = ChurnConfig(department_id=user.department_id)
        db.add(config)
        await db.commit()
        await db.refresh(config)
    return {
        "id": str(config.id),
        "inactivity_days": config.inactivity_days,
        "low_satisfaction_threshold": config.low_satisfaction_threshold,
        "auto_notify": config.auto_notify,
        "notify_emails": config.notify_emails,
    }


@router.put("/churn-config")
async def update_churn_config(
    body: ChurnConfigUpdate,
    db: AsyncSession = Depends(get_db),
    user: User = Depends(get_current_user),
):
    result = await db.execute(
        select(ChurnConfig).where(ChurnConfig.department_id == user.department_id)
    )
    config = result.scalar_one_or_none()
    if not config:
        config = ChurnConfig(department_id=user.department_id)
        db.add(config)
    for field, val in body.model_dump(exclude_unset=True).items():
        setattr(config, field, val)
    await db.commit()
    await db.refresh(config)
    return {"message": "已更新"}


@router.get("/churn-warnings")
async def list_churn_warnings(
    customer_id: str = "",
    risk_level: str = "",
    resolved: bool | None = None,
    limit: int = 50,
    offset: int = 0,
    db: AsyncSession = Depends(get_db),
    user: User = Depends(get_current_user),
):
    query = select(ChurnWarning).order_by(ChurnWarning.created_at.desc())
    if customer_id:
        query = query.where(ChurnWarning.customer_id == uuid.UUID(customer_id))
    if risk_level:
        query = query.where(ChurnWarning.risk_level == risk_level)
    if resolved is not None:
        query = query.where(ChurnWarning.resolved == resolved)
    result = await db.execute(query.offset(offset).limit(limit))
    rows = result.scalars().all()
    return {
        "items": [
            {
                "id": str(w.id),
                "customer_id": str(w.customer_id),
                "risk_level": w.risk_level,
                "reason": w.reason,
                "resolved": w.resolved,
                "resolved_at": w.resolved_at.isoformat() if w.resolved_at else None,
                "created_at": w.created_at.isoformat() if w.created_at else None,
            }
            for w in rows
        ]
    }


@router.post("/customers/{customer_id}/check-churn")
async def check_churn(
    customer_id: str,
    request: Request = None,
    db: AsyncSession = Depends(get_db),
    user: User = Depends(get_current_user),
):
    c = await _get_customer(customer_id, db, user)
    config = (await db.execute(
        select(ChurnConfig).where(ChurnConfig.department_id == user.department_id)
    )).scalar_one_or_none()

    inactivity_days = config.inactivity_days if config else 90
    low_threshold = config.low_satisfaction_threshold if config else 40

    reasons = []

    # Check inactivity
    latest_behavior = (await db.execute(
        select(func.max(CustomerBehavior.event_date))
        .where(CustomerBehavior.customer_id == uuid.UUID(customer_id))
    )).scalar()
    if latest_behavior:
        days_inactive = (_now() - latest_behavior.replace(tzinfo=timezone.utc)).days
        if days_inactive > inactivity_days:
            reasons.append(f"最近互动{days_inactive}天前（阈值{inactivity_days}天）")
    else:
        reasons.append("无行为记录")

    # Check satisfaction
    latest_satisfaction = (await db.execute(
        select(CustomerSatisfaction)
        .where(CustomerSatisfaction.customer_id == uuid.UUID(customer_id))
        .order_by(CustomerSatisfaction.survey_date.desc())
        .limit(1)
    )).scalar_one_or_none()
    if latest_satisfaction and latest_satisfaction.score < low_threshold:
        reasons.append(f"最近满意度{latest_satisfaction.score}分（阈值{low_threshold}分）")

    if not reasons:
        return {"warning": None, "message": "该客户状态良好"}

    risk = "high" if len(reasons) >= 2 else "medium"
    w = ChurnWarning(
        customer_id=uuid.UUID(customer_id),
        risk_level=risk,
        reason="; ".join(reasons),
    )
    db.add(w)
    await db.commit()
    await db.refresh(w)
    await audit_log(db, user, "churn_warning_create", "churn_warning", w.id, risk, "success", request=request)
    return {
        "warning": {
            "id": str(w.id),
            "customer_id": str(w.customer_id),
            "risk_level": w.risk_level,
            "reason": w.reason,
        }
    }


@router.put("/churn-warnings/{warning_id}/resolve")
async def resolve_warning(
    warning_id: str,
    db: AsyncSession = Depends(get_db),
    user: User = Depends(get_current_user),
):
    result = await db.execute(
        select(ChurnWarning).where(ChurnWarning.id == uuid.UUID(warning_id))
    )
    w = result.scalar_one_or_none()
    if not w:
        raise HTTPException(status_code=404, detail="预警不存在")
    w.resolved = True
    w.resolved_at = _now()
    await db.commit()
    return {"message": "已解决"}


# ── Demand Prediction (LLM) ──

DEMAND_PREDICTION_PROMPT = """你是一个客户需求分析专家。根据以下客户信息，预测客户未来可能的需求。

客户名称：{name}
客户行业：{industry}
客户状态：{status}
最近行为事件：
{behaviors}
最近满意度评分：
{satisfaction}

请分析并返回JSON格式的结果：
{{
  "predicted_needs": ["需求1", "需求2"],
  "confidence": "high|medium|low",
  "recommended_actions": ["行动建议1", "行动建议2"],
  "risk_factors": ["风险因素1"],
  "summary": "一段话总结"
}}"""


@router.post("/customers/{customer_id}/predict-demand")
async def predict_demand(
    customer_id: str,
    request: Request = None,
    db: AsyncSession = Depends(get_db),
    user: User = Depends(get_current_user),
):
    c = await _get_customer(customer_id, db, user)

    behaviors_result = await db.execute(
        select(CustomerBehavior)
        .where(CustomerBehavior.customer_id == uuid.UUID(customer_id))
        .order_by(CustomerBehavior.event_date.desc())
        .limit(10)
    )
    behaviors = behaviors_result.scalars().all()
    behaviors_text = "\n".join(
        f"- {b.event_date.strftime('%Y-%m-%d') if b.event_date else ''} [{b.event_type}] {b.description}"
        for b in behaviors
    ) or "无记录"

    sat_result = await db.execute(
        select(CustomerSatisfaction)
        .where(CustomerSatisfaction.customer_id == uuid.UUID(customer_id))
        .order_by(CustomerSatisfaction.survey_date.desc())
        .limit(5)
    )
    satisfactions = sat_result.scalars().all()
    sat_text = ", ".join(f"{s.score}分" for s in satisfactions) or "无记录"

    prompt = DEMAND_PREDICTION_PROMPT.format(
        name=c.name,
        industry=c.industry,
        status=c.status,
        behaviors=behaviors_text,
        satisfaction=sat_text,
    )

    llm = get_llm()
    try:
        resp = await llm.generate(
            system_prompt="你是一个专业的企业客户需求分析系统。请严格返回JSON格式。",
            user_prompt=prompt,
            config=LLMConfig(temperature=0.3, max_tokens=4096),
        )
    except Exception as e:
        raise HTTPException(status_code=502, detail=f"LLM调用失败: {e}")

    await audit_log(db, user, "demand_prediction", "customer", c.id, c.name, "success", f"model={resp.model}", request=request)
    return {
        "customer_id": str(c.id),
        "customer_name": c.name,
        "content": resp.content,
        "model": resp.model,
    }


# ── Marketing Proposals ──

PROPOSAL_SYSTEM_PROMPT = """你是一个专业的市场营销方案撰写专家。你的任务是根据客户信息和需求，撰写一份详细的市场营销方案。

方案应包含以下结构：
1. 客户背景分析
2. 市场机会与挑战
3. 营销策略建议
4. 执行计划与时间线
5. 预算估算
6. 预期效果与KPI

请使用Markdown格式输出，标题使用##。"""


@router.get("/proposals")
async def list_proposals(
    customer_id: str = "",
    status: str = "",
    limit: int = 50,
    offset: int = 0,
    db: AsyncSession = Depends(get_db),
    user: User = Depends(get_current_user),
):
    query = select(MarketingProposal).order_by(MarketingProposal.updated_at.desc())
    if user.role != "admin":
        if user.department_id:
            query = query.where(MarketingProposal.department_id == user.department_id)
        else:
            query = query.where(MarketingProposal.created_by == user.id)
    if customer_id:
        query = query.where(MarketingProposal.customer_id == uuid.UUID(customer_id))
    if status:
        query = query.where(MarketingProposal.status == status)
    result = await db.execute(query.offset(offset).limit(limit))
    rows = result.scalars().all()
    return {
        "items": [
            {
                "id": str(p.id),
                "customer_id": str(p.customer_id) if p.customer_id else None,
                "title": p.title,
                "status": p.status,
                "content_preview": p.content[:200] if p.content else "",
                "created_by": str(p.created_by) if p.created_by else None,
                "created_at": p.created_at.isoformat() if p.created_at else None,
                "updated_at": p.updated_at.isoformat() if p.updated_at else None,
            }
            for p in rows
        ]
    }


@router.post("/proposals/generate")
async def generate_proposal(
    body: ProposalGenerateRequest,
    request: Request = None,
    db: AsyncSession = Depends(get_db),
    user: User = Depends(get_current_user),
):
    customer_name = "通用"
    if body.customer_id:
        try:
            c = await _get_customer(body.customer_id, db, user)
            customer_name = c.name
        except HTTPException:
            pass

    user_prompt = f"请为以下客户撰写营销方案：\n\n客户：{customer_name}\n主题：{body.topic or body.title}\n需求：{body.requirements}\n补充信息：{body.additional_info}"

    llm = get_llm()
    try:
        resp = await llm.generate(
            system_prompt=PROPOSAL_SYSTEM_PROMPT,
            user_prompt=user_prompt,
            config=LLMConfig(temperature=0.7, max_tokens=4096),
        )
    except Exception as e:
        raise HTTPException(status_code=502, detail=f"LLM调用失败: {e}")

    p = MarketingProposal(
        customer_id=uuid.UUID(body.customer_id) if body.customer_id else None,
        title=body.title,
        content=resp.content,
        content_html=_md_to_html(resp.content),
        status="draft",
        department_id=user.department_id,
        created_by=user.id,
    )
    db.add(p)
    await db.commit()
    await db.refresh(p)

    await audit_log(db, user, "proposal_generate", "marketing_proposal", p.id, p.title, "success", f"model={resp.model}", request=request)
    return {
        "id": str(p.id),
        "title": p.title,
        "content": resp.content,
        "content_html": p.content_html,
        "model": resp.model,
        "status": p.status,
    }


@router.get("/proposals/{proposal_id}")
async def get_proposal(
    proposal_id: str,
    db: AsyncSession = Depends(get_db),
    user: User = Depends(get_current_user),
):
    result = await db.execute(
        select(MarketingProposal).where(MarketingProposal.id == uuid.UUID(proposal_id))
    )
    p = result.scalar_one_or_none()
    if not p:
        raise HTTPException(status_code=404, detail="方案不存在")
    if user.role != "admin" and user.department_id and p.department_id != user.department_id:
        raise HTTPException(status_code=403, detail="无权访问")
    return {
        "id": str(p.id),
        "customer_id": str(p.customer_id) if p.customer_id else None,
        "title": p.title,
        "content": p.content,
        "content_html": p.content_html,
        "status": p.status,
        "created_by": str(p.created_by) if p.created_by else None,
        "created_at": p.created_at.isoformat() if p.created_at else None,
        "updated_at": p.updated_at.isoformat() if p.updated_at else None,
    }


@router.put("/proposals/{proposal_id}")
async def update_proposal(
    proposal_id: str,
    body: ProposalUpdate,
    request: Request = None,
    db: AsyncSession = Depends(get_db),
    user: User = Depends(get_current_user),
):
    result = await db.execute(
        select(MarketingProposal).where(MarketingProposal.id == uuid.UUID(proposal_id))
    )
    p = result.scalar_one_or_none()
    if not p:
        raise HTTPException(status_code=404, detail="方案不存在")
    if user.role != "admin" and user.department_id and p.department_id != user.department_id:
        raise HTTPException(status_code=403, detail="无权访问")
    for field, val in body.model_dump(exclude_unset=True).items():
        setattr(p, field, val)
    await db.commit()
    await db.refresh(p)
    await audit_log(db, user, "proposal_update", "marketing_proposal", p.id, p.title, "success", request=request)
    return {"message": "已更新"}


@router.delete("/proposals/{proposal_id}")
async def delete_proposal(
    proposal_id: str,
    request: Request = None,
    db: AsyncSession = Depends(get_db),
    user: User = Depends(get_current_user),
):
    result = await db.execute(
        select(MarketingProposal).where(MarketingProposal.id == uuid.UUID(proposal_id))
    )
    p = result.scalar_one_or_none()
    if not p:
        raise HTTPException(status_code=404, detail="方案不存在")
    await db.delete(p)
    await db.commit()
    await audit_log(db, user, "proposal_delete", "marketing_proposal", p.id, p.title, "success", request=request)
    return {"message": "已删除"}


# ── 3.2: Marketing Projects ──

@router.get("/projects")
async def list_projects(
    customer_id: str = "",
    stage: str = "",
    limit: int = 50,
    offset: int = 0,
    db: AsyncSession = Depends(get_db),
    user: User = Depends(get_current_user),
):
    query = select(MarketingProject).order_by(MarketingProject.updated_at.desc())
    if user.role != "admin":
        if user.department_id:
            query = query.where(MarketingProject.department_id == user.department_id)
        else:
            query = query.where(MarketingProject.created_by == user.id)
    if customer_id:
        query = query.where(MarketingProject.customer_id == uuid.UUID(customer_id))
    if stage:
        query = query.where(MarketingProject.stage == stage)
    result = await db.execute(query.offset(offset).limit(limit))
    rows = result.scalars().all()
    return {"items": [_project_row(p) for p in rows]}


@router.post("/projects")
async def create_project(
    body: ProjectCreate,
    request: Request = None,
    db: AsyncSession = Depends(get_db),
    user: User = Depends(get_current_user),
):
    p = MarketingProject(
        customer_id=uuid.UUID(body.customer_id) if body.customer_id else None,
        name=body.name,
        stage=body.stage,
        data_sources=body.data_sources,
        department_id=user.department_id,
        created_by=user.id,
    )
    db.add(p)
    await db.commit()
    await db.refresh(p)
    await audit_log(db, user, "project_create", "marketing_project", p.id, p.name, "success", request=request)
    return _project_row(p)


@router.get("/projects/{project_id}")
async def get_project(
    project_id: str,
    db: AsyncSession = Depends(get_db),
    user: User = Depends(get_current_user),
):
    p = await _get_project(project_id, db, user)
    return _project_row(p)


@router.put("/projects/{project_id}")
async def update_project(
    project_id: str,
    body: ProjectUpdate,
    request: Request = None,
    db: AsyncSession = Depends(get_db),
    user: User = Depends(get_current_user),
):
    p = await _get_project(project_id, db, user)
    for field, val in body.model_dump(exclude_unset=True).items():
        setattr(p, field, val)
    await db.commit()
    await db.refresh(p)
    await audit_log(db, user, "project_update", "marketing_project", p.id, p.name, "success", request=request)
    return _project_row(p)


@router.delete("/projects/{project_id}")
async def delete_project(
    project_id: str,
    request: Request = None,
    db: AsyncSession = Depends(get_db),
    user: User = Depends(get_current_user),
):
    p = await _get_project(project_id, db, user)
    await db.delete(p)
    await db.commit()
    await audit_log(db, user, "project_delete", "marketing_project", p.id, p.name, "success", request=request)
    return {"message": "已删除"}


@router.get("/projects/{project_id}/timeline")
async def project_timeline(
    project_id: str,
    db: AsyncSession = Depends(get_db),
    user: User = Depends(get_current_user),
):
    p = await _get_project(project_id, db, user)
    events: list[dict] = []

    # Behaviors for linked customer
    if p.customer_id:
        b_result = await db.execute(
            select(CustomerBehavior)
            .where(CustomerBehavior.customer_id == p.customer_id)
            .order_by(CustomerBehavior.event_date.desc())
            .limit(30)
        )
        for b in b_result.scalars().all():
            events.append({
                "type": "behavior",
                "date": b.event_date.isoformat() if b.event_date else None,
                "title": b.event_type,
                "detail": b.description,
            })

    # Briefs
    brief_result = await db.execute(
        select(ProjectBrief)
        .where(ProjectBrief.project_id == uuid.UUID(project_id))
        .order_by(ProjectBrief.created_at.desc())
    )
    for brief in brief_result.scalars().all():
        events.append({
            "type": "brief",
            "date": brief.created_at.isoformat() if brief.created_at else None,
            "title": "项目简报",
            "detail": brief.content[:300],
        })

    events.sort(key=lambda e: e["date"] or "", reverse=True)
    return {"project": _project_row(p), "events": events}


BRIEF_SYSTEM_PROMPT = """你是一个专业的项目分析师。根据以下项目信息撰写项目简报。

简报应包含：
1. 项目概况
2. 当前进展
3. 关键发现
4. 风险与建议
5. 下一步计划

请使用Markdown格式输出。"""


@router.post("/projects/{project_id}/brief")
async def generate_brief(
    project_id: str,
    body: BriefGenerateRequest = BriefGenerateRequest(),
    request: Request = None,
    db: AsyncSession = Depends(get_db),
    user: User = Depends(get_current_user),
):
    p = await _get_project(project_id, db, user)

    customer_name = "未关联"
    if p.customer_id:
        c_result = await db.execute(select(Customer).where(Customer.id == p.customer_id))
        c = c_result.scalar_one_or_none()
        if c:
            customer_name = c.name

    user_prompt = f"项目名称：{p.name}\n当前阶段：{p.stage}\n关联客户：{customer_name}\n补充信息：{body.additional_info}"

    llm = get_llm()
    try:
        resp = await llm.generate(
            system_prompt=BRIEF_SYSTEM_PROMPT,
            user_prompt=user_prompt,
            config=LLMConfig(temperature=0.5, max_tokens=2048),
        )
    except Exception as e:
        raise HTTPException(status_code=502, detail=f"LLM调用失败: {e}")

    brief = ProjectBrief(
        project_id=uuid.UUID(project_id),
        content=resp.content,
        content_html=_md_to_html(resp.content),
        generated_by=user.id,
    )
    db.add(brief)
    await db.commit()
    await db.refresh(brief)

    await audit_log(db, user, "brief_generate", "project_brief", brief.id, p.name, "success", f"model={resp.model}", request=request)
    return {
        "id": str(brief.id),
        "content": resp.content,
        "content_html": brief.content_html,
        "model": resp.model,
    }


# ── 3.2: Community ──

SENTIMENT_ANALYSIS_PROMPT = """分析以下社群消息的情感。返回JSON：{"sentiment": "positive|neutral|negative", "score": 0.0-1.0, "tags": ["标签1", "标签2"]}

消息内容："""


@router.get("/community/interactions")
async def list_interactions(
    platform: str = "",
    group_name: str = "",
    sentiment: str = "",
    limit: int = 50,
    offset: int = 0,
    db: AsyncSession = Depends(get_db),
    user: User = Depends(get_current_user),
):
    query = select(CommunityInteraction).order_by(CommunityInteraction.interaction_date.desc())
    if user.role != "admin":
        if user.department_id:
            query = query.where(CommunityInteraction.department_id == user.department_id)
        else:
            query = query.where(CommunityInteraction.recorded_by == user.id)
    if platform:
        query = query.where(CommunityInteraction.platform == platform)
    if group_name:
        query = query.where(CommunityInteraction.group_name.ilike(f"%{group_name}%"))
    if sentiment:
        query = query.where(CommunityInteraction.sentiment == sentiment)
    result = await db.execute(query.offset(offset).limit(limit))
    rows = result.scalars().all()
    return {"items": [_interaction_row(i) for i in rows]}


@router.post("/community/interactions")
async def record_interaction(
    body: InteractionCreate,
    request: Request = None,
    db: AsyncSession = Depends(get_db),
    user: User = Depends(get_current_user),
):
    tags = body.tags

    # LLM sentiment analysis
    try:
        llm = get_llm()
        resp = await llm.generate(
            system_prompt="你是一个社群情感分析系统。严格按JSON格式返回结果。",
            user_prompt=SENTIMENT_ANALYSIS_PROMPT + body.content,
            config=LLMConfig(temperature=0.1, max_tokens=256),
        )
        import json
        analysis = json.loads(resp.content)
        sentiment = analysis.get("sentiment", "neutral")
        sentiment_score = float(analysis.get("score", 0.0))
        if not tags:
            tags = analysis.get("tags", [])
    except Exception:
        sentiment = "neutral"
        sentiment_score = 0.0

    interaction_date = datetime.fromisoformat(body.interaction_date) if body.interaction_date else _now()
    i = CommunityInteraction(
        platform=body.platform,
        group_name=body.group_name,
        user_name=body.user_name,
        content=body.content,
        sentiment=sentiment,
        sentiment_score=sentiment_score,
        tags=tags,
        interaction_date=interaction_date,
        department_id=user.department_id,
        recorded_by=user.id,
    )
    db.add(i)
    await db.commit()
    await db.refresh(i)
    await audit_log(db, user, "interaction_record", "community_interaction", i.id, i.user_name, "success", request=request)
    return _interaction_row(i)


@router.get("/community/activity")
async def community_activity(
    platform: str = "",
    group_name: str = "",
    days: int = 30,
    db: AsyncSession = Depends(get_db),
    user: User = Depends(get_current_user),
):
    since_date = _now() - timedelta(days=days)
    query = select(CommunityDailyStat).order_by(CommunityDailyStat.date.asc())
    query = query.where(CommunityDailyStat.date >= since_date)
    if user.role != "admin" and user.department_id:
        query = query.where(CommunityDailyStat.department_id == user.department_id)
    if platform:
        query = query.where(CommunityDailyStat.platform == platform)
    if group_name:
        query = query.where(CommunityDailyStat.group_name.ilike(f"%{group_name}%"))
    result = await db.execute(query)
    rows = result.scalars().all()
    total_members_by_date: dict[str, int] = {}
    active_by_date: dict[str, int] = {}
    for r in rows:
        d = r.date.strftime("%Y-%m-%d") if r.date else ""
        total_members_by_date[d] = total_members_by_date.get(d, 0) + r.total_members
        active_by_date[d] = active_by_date.get(d, 0) + r.active_users
    return {
        "items": [
            {
                "date": d,
                "total_members": total_members_by_date.get(d, 0),
                "active_users": active_by_date.get(d, 0),
            }
            for d in sorted(total_members_by_date.keys())
        ],
    }


@router.get("/community/hot-topics")
async def community_hot_topics(
    platform: str = "",
    limit: int = 30,
    db: AsyncSession = Depends(get_db),
    user: User = Depends(get_current_user),
):
    query = select(CommunityInteraction.tags).order_by(CommunityInteraction.interaction_date.desc()).limit(limit)
    if user.role != "admin" and user.department_id:
        query = query.where(CommunityInteraction.department_id == user.department_id)
    if platform:
        query = query.where(CommunityInteraction.platform == platform)
    result = await db.execute(query)
    tag_counts: dict[str, int] = {}
    for (tags,) in result.all():
        for t in (tags or []):
            tag_counts[t] = tag_counts.get(t, 0) + 1
    sorted_tags = sorted(tag_counts.items(), key=lambda kv: kv[1], reverse=True)
    return {"topics": [{"tag": t, "count": c} for t, c in sorted_tags[:20]]}


# ── 3.2: Knowledge Base ──

@router.get("/knowledge")
async def list_knowledge(
    category: str = "",
    search: str = "",
    limit: int = 50,
    offset: int = 0,
    db: AsyncSession = Depends(get_db),
    user: User = Depends(get_current_user),
):
    query = select(KnowledgeEntry).order_by(KnowledgeEntry.updated_at.desc())
    if user.role != "admin":
        if user.department_id:
            query = query.where(KnowledgeEntry.department_id == user.department_id)
        else:
            query = query.where(KnowledgeEntry.created_by == user.id)
    if category:
        query = query.where(KnowledgeEntry.category == category)
    if search:
        query = query.where(
            KnowledgeEntry.title.ilike(f"%{search}%")
            | KnowledgeEntry.content.ilike(f"%{search}%")
        )
    result = await db.execute(query.offset(offset).limit(limit))
    rows = result.scalars().all()
    return {"items": [_knowledge_row(k) for k in rows]}


@router.post("/knowledge")
async def create_knowledge(
    body: KnowledgeEntryCreate,
    request: Request = None,
    db: AsyncSession = Depends(get_db),
    user: User = Depends(get_current_user),
):
    k = KnowledgeEntry(
        title=body.title,
        content=body.content,
        category=body.category,
        tags=body.tags,
        department_id=user.department_id,
        created_by=user.id,
    )
    db.add(k)
    await db.commit()
    await db.refresh(k)
    await audit_log(db, user, "knowledge_create", "knowledge_entry", k.id, k.title, "success", request=request)
    return _knowledge_row(k)


@router.post("/knowledge/upload")
async def upload_knowledge(
    file: UploadFile = FastAPIFile(...),
    category: str = "",
    tags: str = "",
    request: Request = None,
    db: AsyncSession = Depends(get_db),
    user: User = Depends(get_current_user),
):
    contents = await file.read()
    storage_path = f"knowledge/{uuid.uuid4()}/{file.filename}"

    await upload_file(storage_path, contents, file.content_type or "application/octet-stream")

    file_record = File(
        name=file.filename,
        is_folder=False,
        mime_type=file.content_type or "",
        size_bytes=len(contents),
        storage_path=storage_path,
        uploaded_by=user.id,
    )
    db.add(file_record)
    await db.commit()
    await db.refresh(file_record)

    extracted = await extract_text(contents, file.filename)
    tag_list = [t.strip() for t in tags.split(",") if t.strip()] if tags else []

    k = KnowledgeEntry(
        title=file.filename,
        content=extracted,
        category=category,
        tags=tag_list,
        source_file_id=file_record.id,
        department_id=user.department_id,
        created_by=user.id,
    )
    db.add(k)
    await db.commit()
    await db.refresh(k)

    await audit_log(db, user, "knowledge_upload", "knowledge_entry", k.id, k.title, "success", f"file={file.filename}", request=request)
    return _knowledge_row(k)


@router.get("/knowledge/{entry_id}/file-url")
async def knowledge_file_url(
    entry_id: str,
    db: AsyncSession = Depends(get_db),
    user: User = Depends(get_current_user),
):
    result = await db.execute(select(KnowledgeEntry).where(KnowledgeEntry.id == uuid.UUID(entry_id)))
    k = result.scalar_one_or_none()
    if not k or not k.source_file_id:
        raise HTTPException(status_code=404, detail="文件不存在")
    result2 = await db.execute(select(File).where(File.id == k.source_file_id))
    f = result2.scalar_one_or_none()
    if not f:
        raise HTTPException(status_code=404, detail="源文件不存在")
    url = await get_presigned_url(f.storage_path)
    return {"url": url, "name": f.name, "mime_type": f.mime_type, "size_bytes": f.size_bytes}


@router.delete("/knowledge/{entry_id}/file")
async def knowledge_file_delete(
    entry_id: str,
    request: Request = None,
    db: AsyncSession = Depends(get_db),
    user: User = Depends(get_current_user),
):
    result = await db.execute(select(KnowledgeEntry).where(KnowledgeEntry.id == uuid.UUID(entry_id)))
    k = result.scalar_one_or_none()
    if not k or not k.source_file_id:
        raise HTTPException(status_code=404, detail="文件不存在")
    fid = k.source_file_id
    result2 = await db.execute(select(File).where(File.id == fid))
    f = result2.scalar_one_or_none()
    if f:
        await delete_file(f.storage_path)
        await db.delete(f)
    k.source_file_id = None
    k.content = ""
    await db.commit()
    await audit_log(db, user, "knowledge_file_delete", "knowledge_entry", k.id, k.title, "success", request=request)
    return {"message": "文件已删除"}


@router.put("/knowledge/{entry_id}")
async def update_knowledge(
    entry_id: str,
    body: KnowledgeEntryUpdate,
    request: Request = None,
    db: AsyncSession = Depends(get_db),
    user: User = Depends(get_current_user),
):
    result = await db.execute(select(KnowledgeEntry).where(KnowledgeEntry.id == uuid.UUID(entry_id)))
    k = result.scalar_one_or_none()
    if not k:
        raise HTTPException(status_code=404, detail="知识条目不存在")
    for field, val in body.model_dump(exclude_unset=True).items():
        setattr(k, field, val)
    await db.commit()
    await db.refresh(k)
    await audit_log(db, user, "knowledge_update", "knowledge_entry", k.id, k.title, "success", request=request)
    return _knowledge_row(k)


@router.delete("/knowledge/{entry_id}")
async def delete_knowledge(
    entry_id: str,
    request: Request = None,
    db: AsyncSession = Depends(get_db),
    user: User = Depends(get_current_user),
):
    result = await db.execute(select(KnowledgeEntry).where(KnowledgeEntry.id == uuid.UUID(entry_id)))
    k = result.scalar_one_or_none()
    if not k:
        raise HTTPException(status_code=404, detail="知识条目不存在")
    await db.delete(k)
    await db.commit()
    await audit_log(db, user, "knowledge_delete", "knowledge_entry", k.id, k.title, "success", request=request)
    return {"message": "已删除"}


QA_SYSTEM_PROMPT = """你是公司内部知识助手，根据知识库资料回答同事的问题。回答前必须先逐篇判断每篇资料与问题的相关性，再进行回答。

注意：语义相关不要求关键词一致。比如用户问"AI方向做了什么"，资料里"智能客服系统上线"就是高度相关。

只有在逐篇判断后发现确实没有任何资料与问题相关时，才用自己的知识回答并标注⚠️以上内容由AI生成，非公司内部资料，仅供参考。不确定就说"这块我还不太确定"。

保持自然、专业的同事聊天风格。"""

QA_HISTORY_WRAP_PROMPT = """之前和用户的对话：
{history}

根据上面的对话历史，结合知识库内容，自然地回答用户的最新问题。注意上下文连贯，就像在继续刚才的聊天。"""


@router.post("/knowledge/qa")
async def knowledge_qa(
    body: KnowledgeQARequest,
    request: Request = None,
    db: AsyncSession = Depends(get_db),
    user: User = Depends(get_current_user),
):
    # Fetch all knowledge entries for this user/department
    base_query = select(KnowledgeEntry).order_by(KnowledgeEntry.updated_at.desc())
    if user.role != "admin":
        if user.department_id:
            base_query = base_query.where(KnowledgeEntry.department_id == user.department_id)
        else:
            base_query = base_query.where(KnowledgeEntry.created_by == user.id)
    result = await db.execute(base_query.limit(50))
    all_entries = result.scalars().all()

    # Build knowledge base catalog for LLM to search through
    if all_entries:
        catalog_parts = []
        for i, k in enumerate(all_entries, 1):
            # Show full content so LLM can do semantic matching
            catalog_parts.append(f"[{i}] 标题: {k.title}\n内容: {k.content[:2000]}")
        catalog = "\n\n---\n\n".join(catalog_parts)
        instruction = f"""以下是公司知识库的全部{len(all_entries)}篇资料。请按以下步骤处理：

第一步：逐篇判断是否与用户问题相关，给出你的判断（相关/不相关+理由）
第二步：用相关的资料来回答用户问题，先引用原文关键内容，再给分析

知识库资料：
{catalog}

回答格式：
【相关性判断】
第1篇：相关/不相关 — 理由
第2篇：相关/不相关 — 理由
...
【回答】
（你的回答内容）
【来源】第X篇、第Y篇"""
    else:
        instruction = "（知识库中暂无资料）"

    # Build user prompt with optional history
    if body.history:
        history_str = "\n".join(
            f"{'👤 用户' if h['role'] == 'user' else '🤖 助手'}：{h['content']}"
            for h in body.history[-10:]
        )
        user_prompt = f"{instruction}\n\n{QA_HISTORY_WRAP_PROMPT.format(history=history_str)}\n\n用户最新问题：{body.question}"
    else:
        user_prompt = f"{instruction}\n\n用户问题：{body.question}"

    sources = [
        {
            "id": str(k.id), "title": k.title, "content_preview": k.content[:150],
            "source_file_id": str(k.source_file_id) if k.source_file_id else None,
        }
        for k in all_entries
    ]

    llm = get_llm()
    try:
        resp = await llm.generate(
            system_prompt=QA_SYSTEM_PROMPT,
            user_prompt=user_prompt,
            config=LLMConfig(temperature=0.3, max_tokens=4096),
        )
    except Exception as e:
        raise HTTPException(status_code=502, detail=f"LLM调用失败: {e}")

    # Save QA record
    qa = QAChatRecord(
        user_id=user.id,
        question=body.question,
        answer=resp.content,
        sources=sources,
        model=resp.model,
    )
    db.add(qa)
    await db.commit()

    await audit_log(db, user, "knowledge_qa", "qa_chat_record", qa.id, body.question[:100], "success", f"model={resp.model}", request=request)
    return {"answer": resp.content, "sources": sources, "model": resp.model}


@router.get("/knowledge/qa-history")
async def qa_history(
    limit: int = 50,
    offset: int = 0,
    db: AsyncSession = Depends(get_db),
    user: User = Depends(get_current_user),
):
    query = select(QAChatRecord).where(QAChatRecord.user_id == user.id).order_by(QAChatRecord.created_at.desc())
    result = await db.execute(query.offset(offset).limit(limit))
    rows = result.scalars().all()
    return {
        "items": [
            {
                "id": str(r.id),
                "question": r.question,
                "answer": r.answer,
                "sources": r.sources,
                "model": r.model,
                "created_at": r.created_at.isoformat() if r.created_at else None,
            }
            for r in rows
        ]
    }


# ── Helpers ──

def _project_row(p: MarketingProject) -> dict:
    return {
        "id": str(p.id),
        "customer_id": str(p.customer_id) if p.customer_id else None,
        "name": p.name,
        "stage": p.stage,
        "data_sources": p.data_sources,
        "department_id": str(p.department_id) if p.department_id else None,
        "created_by": str(p.created_by) if p.created_by else None,
        "created_at": p.created_at.isoformat() if p.created_at else None,
        "updated_at": p.updated_at.isoformat() if p.updated_at else None,
    }


def _interaction_row(i: CommunityInteraction) -> dict:
    return {
        "id": str(i.id),
        "platform": i.platform,
        "group_name": i.group_name,
        "user_name": i.user_name,
        "content": i.content,
        "sentiment": i.sentiment,
        "sentiment_score": i.sentiment_score,
        "tags": i.tags,
        "interaction_date": i.interaction_date.isoformat() if i.interaction_date else None,
        "department_id": str(i.department_id) if i.department_id else None,
    }


def _knowledge_row(k: KnowledgeEntry) -> dict:
    return {
        "id": str(k.id),
        "title": k.title,
        "content": k.content,
        "content_preview": k.content[:300] if k.content else "",
        "category": k.category,
        "tags": k.tags,
        "source_file_id": str(k.source_file_id) if k.source_file_id else None,
        "created_by": str(k.created_by) if k.created_by else None,
        "created_at": k.created_at.isoformat() if k.created_at else None,
        "updated_at": k.updated_at.isoformat() if k.updated_at else None,
    }


async def _get_project(project_id: str, db: AsyncSession, user: User) -> MarketingProject:
    result = await db.execute(
        select(MarketingProject).where(MarketingProject.id == uuid.UUID(project_id))
    )
    p = result.scalar_one_or_none()
    if not p:
        raise HTTPException(status_code=404, detail="项目不存在")
    if user.role != "admin" and user.department_id and p.department_id != user.department_id:
        raise HTTPException(status_code=403, detail="无权访问")
    return p


# ── MD-to-HTML helper ──

def _md_to_html(md: str) -> str:
    import re
    lines = md.split('\n')
    html_lines = ['<!DOCTYPE html><html lang="zh-CN"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><style>*{margin:0;padding:0;box-sizing:border-box}body{font-family:-apple-system,BlinkMacSystemFont,"Segoe UI",sans-serif;font-size:15px;line-height:1.8;color:#333;padding:20px;max-width:800px;margin:0 auto}h2{font-size:20px;margin:20px 0 10px;color:#1a1a1a}h3{font-size:17px;margin:16px 0 8px;color:#333}ul,ol{padding-left:20px;margin:8px 0}li{margin:4px 0}strong{color:#1a1a1a}p{margin:8px 0}code{background:#f5f5f5;padding:2px 6px;border-radius:4px;font-size:13px}pre{background:#f5f5f5;padding:12px;border-radius:8px;overflow-x:auto}blockquote{border-left:3px solid #7c3aed;padding-left:12px;color:#666;margin:8px 0}</style></head><body>']
    in_code_block = False
    for line in lines:
        if line.startswith('```'):
            in_code_block = not in_code_block
            html_lines.append('</pre>' if not in_code_block else '<pre>')
            continue
        if in_code_block:
            html_lines.append(line)
            continue
        if not line.strip():
            html_lines.append('<br>')
        elif line.startswith('## '):
            html_lines.append(f'<h2>{line[3:]}</h2>')
        elif line.startswith('### '):
            html_lines.append(f'<h3>{line[4:]}</h3>')
        elif line.startswith('- '):
            html_lines.append(f'<li>{line[2:]}</li>')
        elif re.match(r'^\d+\.\s', line):
            html_lines.append(f'<li>{re.sub(r"^\d+\.\s", "", line)}</li>')
        elif line.startswith('> '):
            html_lines.append(f'<blockquote>{line[2:]}</blockquote>')
        else:
            html_lines.append(f'<p>{line}</p>')
    html_lines.append('</body></html>')
    return '\n'.join(html_lines)
