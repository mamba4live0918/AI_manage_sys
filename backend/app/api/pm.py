import uuid
from datetime import datetime, timezone

from fastapi import APIRouter, Depends, Form, HTTPException, Request, UploadFile, File as FastAPIFile
from pydantic import BaseModel
from sqlalchemy import select, func
from sqlalchemy.ext.asyncio import AsyncSession

from app.database import get_db
from app.models import User, File, PmProject, VisitLog, Courseware, ProjectReport
from app.security import get_current_user
from app.services.llm.router import get_llm
from app.services.audit import log as audit_log
from app.services.search import index_document as es_index, delete_document as es_delete
from app.services.storage import upload_file

router = APIRouter(prefix="/pm", tags=["pm"])


def _now():
    return datetime.now(timezone.utc)


# ── Pydantic Schemas ──

class ProjectCreate(BaseModel):
    name: str
    customer_id: str | None = None
    stage: str = "initiation"
    start_date: str | None = None
    end_date: str | None = None
    budget: float = 0.0
    description: str = ""


class ProjectUpdate(BaseModel):
    name: str | None = None
    customer_id: str | None = None
    stage: str | None = None
    start_date: str | None = None
    end_date: str | None = None
    budget: float | None = None
    description: str | None = None


class VisitLogCreate(BaseModel):
    content: str = ""
    location: str = ""
    visited_at: str | None = None


class CoursewareCreate(BaseModel):
    project_id: str | None = None
    title: str
    type: str = "document"
    content: str = ""
    file_id: str | None = None


class CoursewareUpdate(BaseModel):
    project_id: str | None = None
    title: str | None = None
    type: str | None = None
    content: str | None = None
    file_id: str | None = None


class ReportGenerateRequest(BaseModel):
    report_type: str = "progress"


# ── Row Serializers ──

def _project_row(p: PmProject) -> dict:
    return {
        "id": str(p.id),
        "name": p.name,
        "customer_id": str(p.customer_id) if p.customer_id else None,
        "stage": p.stage,
        "start_date": p.start_date.isoformat() if p.start_date else None,
        "end_date": p.end_date.isoformat() if p.end_date else None,
        "budget": p.budget,
        "description": p.description,
        "department_id": str(p.department_id) if p.department_id else None,
        "created_by": str(p.created_by) if p.created_by else None,
        "created_at": p.created_at.isoformat() if p.created_at else None,
        "updated_at": p.updated_at.isoformat() if p.updated_at else None,
    }


def _visit_log_row(v: VisitLog) -> dict:
    return {
        "id": str(v.id),
        "project_id": str(v.project_id) if v.project_id else None,
        "content": v.content,
        "location": v.location,
        "visited_at": v.visited_at.isoformat() if v.visited_at else None,
        "recorded_by": str(v.recorded_by) if v.recorded_by else None,
        "created_at": v.created_at.isoformat() if v.created_at else None,
    }


def _courseware_row(c: Courseware) -> dict:
    return {
        "id": str(c.id),
        "project_id": str(c.project_id) if c.project_id else None,
        "title": c.title,
        "type": c.type,
        "content": c.content,
        "file_id": str(c.file_id) if c.file_id else None,
        "version": c.version,
        "department_id": str(c.department_id) if c.department_id else None,
        "created_by": str(c.created_by) if c.created_by else None,
        "created_at": c.created_at.isoformat() if c.created_at else None,
        "updated_at": c.updated_at.isoformat() if c.updated_at else None,
    }


def _report_row(r: ProjectReport) -> dict:
    return {
        "id": str(r.id),
        "project_id": str(r.project_id) if r.project_id else None,
        "report_type": r.report_type,
        "content": r.content,
        "content_html": r.content_html,
        "model": r.model,
        "department_id": str(r.department_id) if r.department_id else None,
        "created_by": str(r.created_by) if r.created_by else None,
        "created_at": r.created_at.isoformat() if r.created_at else None,
    }


# ── Projects ──

@router.get("/projects")
async def list_projects(
    stage: str = "",
    limit: int = 50,
    offset: int = 0,
    db: AsyncSession = Depends(get_db),
    user: User = Depends(get_current_user),
):
    query = select(PmProject).order_by(PmProject.updated_at.desc())
    if user.role != "admin":
        if user.department_id:
            query = query.where(PmProject.department_id == user.department_id)
        else:
            query = query.where(PmProject.created_by == user.id)
    if stage:
        query = query.where(PmProject.stage == stage)
    result = await db.execute(query.offset(offset).limit(limit))
    return {"items": [_project_row(p) for p in result.scalars().all()]}


@router.post("/projects")
async def create_project(
    body: ProjectCreate,
    request: Request = None,
    db: AsyncSession = Depends(get_db),
    user: User = Depends(get_current_user),
):
    start_date = datetime.fromisoformat(body.start_date) if body.start_date else None
    end_date = datetime.fromisoformat(body.end_date) if body.end_date else None
    customer_id = uuid.UUID(body.customer_id) if body.customer_id else None
    p = PmProject(
        name=body.name,
        customer_id=customer_id,
        stage=body.stage,
        start_date=start_date,
        end_date=end_date,
        budget=body.budget,
        description=body.description,
        department_id=user.department_id,
        created_by=user.id,
    )
    db.add(p)
    await db.commit()
    await db.refresh(p)
    await audit_log(db, user, "project_create", "pm_project", p.id, p.name, request=request)
    await es_index(str(p.id), "projects", p.name, p.description or "", extra=p.stage or "", department_id=str(user.department_id) if user.department_id else None)
    return _project_row(p)


@router.get("/projects/{project_id}")
async def get_project(
    project_id: str,
    db: AsyncSession = Depends(get_db),
    user: User = Depends(get_current_user),
):
    result = await db.execute(select(PmProject).where(PmProject.id == project_id))
    p = result.scalar_one_or_none()
    if not p:
        raise HTTPException(404, "项目不存在")
    return _project_row(p)


@router.put("/projects/{project_id}")
async def update_project(
    project_id: str,
    body: ProjectUpdate,
    request: Request = None,
    db: AsyncSession = Depends(get_db),
    user: User = Depends(get_current_user),
):
    result = await db.execute(select(PmProject).where(PmProject.id == project_id))
    p = result.scalar_one_or_none()
    if not p:
        raise HTTPException(404, "项目不存在")
    for k, v in body.model_dump(exclude_none=True).items():
        if k in ("customer_id",) and v is not None:
            setattr(p, k, uuid.UUID(v) if v else None)
        elif k in ("start_date", "end_date") and v is not None:
            setattr(p, k, datetime.fromisoformat(v) if v else None)
        elif v is not None:
            setattr(p, k, v)
    p.updated_at = _now()
    await db.commit()
    await db.refresh(p)
    await audit_log(db, user, "project_update", "pm_project", p.id, p.name, request=request)
    await es_index(str(p.id), "projects", p.name, p.description or "", extra=p.stage or "", department_id=str(user.department_id) if user.department_id else None)
    return _project_row(p)


@router.delete("/projects/{project_id}")
async def delete_project(
    project_id: str,
    request: Request = None,
    db: AsyncSession = Depends(get_db),
    user: User = Depends(get_current_user),
):
    result = await db.execute(select(PmProject).where(PmProject.id == project_id))
    p = result.scalar_one_or_none()
    if not p:
        raise HTTPException(404, "项目不存在")
    await db.delete(p)
    await db.commit()
    await audit_log(db, user, "project_delete", "pm_project", p.id, p.name, request=request)
    await es_delete(str(p.id), "projects")
    return {"ok": True}


# ── Project Report (LLM) ──

@router.post("/projects/{project_id}/report")
async def generate_project_report(
    project_id: str,
    body: ReportGenerateRequest,
    request: Request = None,
    db: AsyncSession = Depends(get_db),
    user: User = Depends(get_current_user),
):
    result = await db.execute(select(PmProject).where(PmProject.id == project_id))
    p = result.scalar_one_or_none()
    if not p:
        raise HTTPException(404, "项目不存在")

    logs_result = await db.execute(
        select(VisitLog).where(VisitLog.project_id == project_id).order_by(VisitLog.visited_at.desc()).limit(20)
    )
    logs = logs_result.scalars().all()
    logs_text = "\n".join(
        f"- [{v.visited_at.strftime('%Y-%m-%d') if v.visited_at else ''}] {v.location}: {v.content[:200]}"
        for v in logs
    )

    prompt = f"""请根据以下项目信息生成一份{body.report_type}报告。

项目名称: {p.name}
阶段: {p.stage}
预算: {p.budget}
描述: {p.description}

近期走访日志:
{logs_text or '暂无'}

请用中文生成一份结构清晰的Markdown格式报告。"""

    llm = get_llm()
    resp = await llm.generate(system_prompt="你是一个专业的项目管理顾问，请生成专业的项目报告。", user_prompt=prompt)
    content = resp.content
    content_html = content

    r = ProjectReport(
        project_id=p.id,
        report_type=body.report_type,
        content=content,
        content_html=content_html,
        model=resp.model,
        department_id=user.department_id,
        created_by=user.id,
    )
    db.add(r)
    await db.commit()
    await db.refresh(r)
    await audit_log(db, user, "report_generate", "project_report", r.id, body.report_type, request=request)
    return _report_row(r)


# ── Visit Logs ──

@router.get("/projects/{project_id}/logs")
async def list_visit_logs(
    project_id: str,
    limit: int = 50,
    offset: int = 0,
    db: AsyncSession = Depends(get_db),
    user: User = Depends(get_current_user),
):
    query = select(VisitLog).where(VisitLog.project_id == project_id).order_by(VisitLog.visited_at.desc())
    result = await db.execute(query.offset(offset).limit(limit))
    return {"items": [_visit_log_row(v) for v in result.scalars().all()]}


@router.post("/projects/{project_id}/logs")
async def create_visit_log(
    project_id: str,
    body: VisitLogCreate,
    request: Request = None,
    db: AsyncSession = Depends(get_db),
    user: User = Depends(get_current_user),
):
    visited_at = datetime.fromisoformat(body.visited_at) if body.visited_at else _now()
    v = VisitLog(
        project_id=uuid.UUID(project_id),
        content=body.content,
        location=body.location,
        visited_at=visited_at,
        recorded_by=user.id,
    )
    db.add(v)
    await db.commit()
    await db.refresh(v)
    await audit_log(db, user, "visit_log_create", "visit_log", v.id, body.location, request=request)
    return _visit_log_row(v)


# ── Coursewares ──

@router.get("/coursewares")
async def list_coursewares(
    project_id: str = "",
    limit: int = 50,
    offset: int = 0,
    db: AsyncSession = Depends(get_db),
    user: User = Depends(get_current_user),
):
    query = select(Courseware).order_by(Courseware.updated_at.desc())
    if user.role != "admin":
        if user.department_id:
            query = query.where(Courseware.department_id == user.department_id)
        else:
            query = query.where(Courseware.created_by == user.id)
    if project_id:
        query = query.where(Courseware.project_id == project_id)
    result = await db.execute(query.offset(offset).limit(limit))
    return {"items": [_courseware_row(c) for c in result.scalars().all()]}


@router.post("/coursewares")
async def create_courseware(
    body: CoursewareCreate,
    request: Request = None,
    db: AsyncSession = Depends(get_db),
    user: User = Depends(get_current_user),
):
    project_id = uuid.UUID(body.project_id) if body.project_id else None
    file_id = uuid.UUID(body.file_id) if body.file_id else None
    c = Courseware(
        project_id=project_id,
        title=body.title,
        type=body.type,
        content=body.content,
        file_id=file_id,
        department_id=user.department_id,
        created_by=user.id,
    )
    db.add(c)
    await db.commit()
    await db.refresh(c)
    await audit_log(db, user, "courseware_create", "courseware", c.id, c.title, request=request)
    await es_index(str(c.id), "coursewares", c.title, c.content or "", extra=c.type or "", department_id=str(user.department_id) if user.department_id else None)
    return _courseware_row(c)


@router.post("/coursewares/upload")
async def upload_courseware(
    file: UploadFile = FastAPIFile(...),
    title: str = Form(""),
    type: str = Form("document"),
    project_id: str = Form(""),
    request: Request = None,
    db: AsyncSession = Depends(get_db),
    user: User = Depends(get_current_user),
):
    content_bytes = await file.read()
    storage_path = f"coursewares/{uuid.uuid4()}/{file.filename}"

    await upload_file(storage_path, content_bytes, file.content_type or "application/octet-stream")

    file_record = File(
        name=file.filename,
        is_folder=False,
        mime_type=file.content_type or "application/octet-stream",
        size_bytes=len(content_bytes),
        storage_path=storage_path,
        uploaded_by=user.id,
    )
    db.add(file_record)
    await db.commit()
    await db.refresh(file_record)

    c = Courseware(
        project_id=uuid.UUID(project_id) if project_id else None,
        title=title.strip() or file.filename,
        type=type,
        content="",
        file_id=file_record.id,
        department_id=user.department_id,
        created_by=user.id,
    )
    db.add(c)
    await db.commit()
    await db.refresh(c)
    await audit_log(db, user, "courseware_upload", "courseware", c.id, c.title, request=request)
    await es_index(str(c.id), "coursewares", c.title, c.content or "", extra=c.type or "", department_id=str(user.department_id) if user.department_id else None)
    return _courseware_row(c)


@router.get("/coursewares/{courseware_id}")
async def get_courseware(
    courseware_id: str,
    db: AsyncSession = Depends(get_db),
    user: User = Depends(get_current_user),
):
    result = await db.execute(select(Courseware).where(Courseware.id == courseware_id))
    c = result.scalar_one_or_none()
    if not c:
        raise HTTPException(404, "课件不存在")
    return _courseware_row(c)


@router.put("/coursewares/{courseware_id}")
async def update_courseware(
    courseware_id: str,
    body: CoursewareUpdate,
    request: Request = None,
    db: AsyncSession = Depends(get_db),
    user: User = Depends(get_current_user),
):
    result = await db.execute(select(Courseware).where(Courseware.id == courseware_id))
    c = result.scalar_one_or_none()
    if not c:
        raise HTTPException(404, "课件不存在")
    for k, v in body.model_dump(exclude_none=True).items():
        if k in ("project_id", "file_id") and v is not None:
            setattr(c, k, uuid.UUID(v) if v else None)
        elif v is not None:
            setattr(c, k, v)
    c.updated_at = _now()
    await db.commit()
    await db.refresh(c)
    await audit_log(db, user, "courseware_update", "courseware", c.id, c.title, request=request)
    await es_index(str(c.id), "coursewares", c.title, c.content or "", extra=c.type or "", department_id=str(user.department_id) if user.department_id else None)
    return _courseware_row(c)


@router.delete("/coursewares/{courseware_id}")
async def delete_courseware(
    courseware_id: str,
    request: Request = None,
    db: AsyncSession = Depends(get_db),
    user: User = Depends(get_current_user),
):
    result = await db.execute(select(Courseware).where(Courseware.id == courseware_id))
    c = result.scalar_one_or_none()
    if not c:
        raise HTTPException(404, "课件不存在")
    await db.delete(c)
    await db.commit()
    await audit_log(db, user, "courseware_delete", "courseware", c.id, c.title, request=request)
    await es_delete(str(c.id), "coursewares")
    return {"ok": True}


# ── PM Stats (charts + calendar) ──

@router.get("/stats")
async def get_pm_stats(
    db: AsyncSession = Depends(get_db),
    user: User = Depends(get_current_user),
):
    base_filter = []
    if user.role != "admin":
        if user.department_id:
            base_filter.append(PmProject.department_id == user.department_id)
        else:
            base_filter.append(PmProject.created_by == user.id)

    stage_query = select(PmProject.stage, func.count(PmProject.id))
    budget_query = select(func.coalesce(func.sum(PmProject.budget), 0))
    proj_query = select(PmProject).order_by(PmProject.start_date.asc().nulls_last())
    logs_query = (
        select(VisitLog, PmProject.name)
        .join(PmProject, VisitLog.project_id == PmProject.id, isouter=True)
        .order_by(VisitLog.visited_at.desc())
        .limit(50)
    )

    for f in base_filter:
        stage_query = stage_query.where(f)
        budget_query = budget_query.where(f)
        proj_query = proj_query.where(f)
        logs_query = logs_query.where(PmProject.department_id == user.department_id) if user.role != "admin" and user.department_id else logs_query

    stage_result = await db.execute(stage_query.group_by(PmProject.stage))
    stages = [{"stage": row[0], "count": row[1]} for row in stage_result.all()]

    budget_result = await db.execute(budget_query)
    total_budget = float(budget_result.scalar() or 0)

    proj_result = await db.execute(proj_query.limit(10))
    projects_budget = [
        {"id": str(p.id), "name": p.name, "budget": p.budget, "stage": p.stage}
        for p in proj_result.scalars().all()
    ]

    proj_result_all = await db.execute(proj_query)
    all_projects = proj_result_all.scalars().all()

    calendar_events = []
    for p in all_projects:
        if p.start_date:
            calendar_events.append({
                "date": p.start_date.strftime("%Y-%m-%d"),
                "title": f"启动: {p.name}",
                "type": "project_start",
                "project_id": str(p.id),
            })
        if p.end_date:
            calendar_events.append({
                "date": p.end_date.strftime("%Y-%m-%d"),
                "title": f"截止: {p.name}",
                "type": "project_end",
                "project_id": str(p.id),
            })

    logs_result = await db.execute(logs_query)
    for row in logs_result.all():
        v, proj_name = row
        if v.visited_at:
            calendar_events.append({
                "date": v.visited_at.strftime("%Y-%m-%d"),
                "title": f"{proj_name or ''}: {v.location or v.content[:30]}",
                "type": "visit_log",
                "project_id": str(v.project_id) if v.project_id else None,
            })

    return {
        "total_projects": len(all_projects),
        "total_budget": total_budget,
        "stages": stages,
        "projects_budget": projects_budget,
        "calendar_events": calendar_events,
    }
