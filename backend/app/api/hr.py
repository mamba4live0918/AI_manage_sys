import uuid
from datetime import datetime, timezone

from fastapi import APIRouter, Depends, Form, HTTPException, Request, UploadFile, File as FastAPIFile
from pydantic import BaseModel
from sqlalchemy import select, func
from sqlalchemy.ext.asyncio import AsyncSession

from app.database import get_db
from app.models import User, File, Resume, Approval, ApprovalStep, Interview
from app.security import get_current_user
from app.services.llm.router import get_llm
from app.services.audit import log as audit_log
from app.services.search import index_document as es_index, delete_document as es_delete
from app.services.file_extractor import extract_text
from app.services.storage import upload_file

router = APIRouter(prefix="/hr", tags=["hr"])


def _now():
    return datetime.now(timezone.utc)


# ── Pydantic Schemas ──

class UserEmployeeUpdate(BaseModel):
    position: str | None = None
    hire_date: str | None = None
    emp_status: str | None = None
    phone: str | None = None
    salary: int | None = None
    contract_start: str | None = None
    contract_end: str | None = None
    file_id: str | None = None
    emp_notes: str | None = None


class ResumeCreate(BaseModel):
    name: str
    content: str = ""
    file_id: str | None = None


class ResumeUpdate(BaseModel):
    name: str | None = None
    content: str | None = None
    status: str | None = None


class ApprovalCreate(BaseModel):
    approval_type: str = "leave"
    content: str = ""
    applicant_id: str | None = None


class ApprovalAction(BaseModel):
    status: str  # approved or rejected
    comment: str = ""


class ApprovalStepAction(BaseModel):
    status: str  # approved or rejected
    comment: str = ""


class InterviewCreate(BaseModel):
    candidate_name: str
    position: str = ""
    scheduled_at: str | None = None
    duration_minutes: int = 30
    interviewer_id: str | None = None
    notes: str = ""


class InterviewUpdate(BaseModel):
    candidate_name: str | None = None
    position: str | None = None
    scheduled_at: str | None = None
    duration_minutes: int | None = None
    status: str | None = None
    interviewer_id: str | None = None
    notes: str | None = None


# ── Row Serializers ──

def _resume_row(r: Resume) -> dict:
    return {
        "id": str(r.id),
        "name": r.name,
        "content": r.content,
        "file_id": str(r.file_id) if r.file_id else None,
        "match_score": r.match_score,
        "match_result": r.match_result,
        "status": r.status,
        "department_id": str(r.department_id) if r.department_id else None,
        "created_by": str(r.created_by) if r.created_by else None,
        "created_at": r.created_at.isoformat() if r.created_at else None,
        "updated_at": r.updated_at.isoformat() if r.updated_at else None,
    }


def _step_row(s: ApprovalStep) -> dict:
    return {
        "id": str(s.id),
        "level": s.level,
        "approver_id": str(s.approver_id) if s.approver_id else None,
        "status": s.status,
        "comment": s.comment,
        "created_at": s.created_at.isoformat() if s.created_at else None,
        "updated_at": s.updated_at.isoformat() if s.updated_at else None,
    }


def _approval_row(a: Approval, steps: list[ApprovalStep] | None = None) -> dict:
    row = {
        "id": str(a.id),
        "approval_type": a.approval_type,
        "applicant_id": str(a.applicant_id) if a.applicant_id else None,
        "status": a.status,
        "content": a.content,
        "approver_id": str(a.approver_id) if a.approver_id else None,
        "comment": a.comment,
        "department_id": str(a.department_id) if a.department_id else None,
        "created_at": a.created_at.isoformat() if a.created_at else None,
        "updated_at": a.updated_at.isoformat() if a.updated_at else None,
    }
    if steps is not None:
        row["steps"] = [_step_row(s) for s in steps]
    return row


def _interview_row(i: Interview) -> dict:
    return {
        "id": str(i.id),
        "candidate_name": i.candidate_name,
        "position": i.position,
        "scheduled_at": i.scheduled_at.isoformat() if i.scheduled_at else None,
        "duration_minutes": i.duration_minutes,
        "status": i.status,
        "interviewer_id": str(i.interviewer_id) if i.interviewer_id else None,
        "notes": i.notes,
        "department_id": str(i.department_id) if i.department_id else None,
        "created_by": str(i.created_by) if i.created_by else None,
        "created_at": i.created_at.isoformat() if i.created_at else None,
        "updated_at": i.updated_at.isoformat() if i.updated_at else None,
    }


_WORKFLOW_LEVELS = {"leave": 2, "expense": 3, "regularization": 2}


# ── Employee (now merged into users) ──

@router.put("/users/{user_id}/employee")
async def update_user_employee(
    user_id: str,
    body: UserEmployeeUpdate,
    request: Request = None,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    if current_user.role != "admin":
        raise HTTPException(403, "仅管理员可操作")
    result = await db.execute(select(User).where(User.id == user_id))
    u = result.scalar_one_or_none()
    if not u:
        raise HTTPException(404, "用户不存在")
    date_fields = {"hire_date", "contract_start", "contract_end"}
    for k, v in body.model_dump(exclude_none=True).items():
        if k in date_fields and v is not None:
            setattr(u, k, datetime.fromisoformat(v) if v else None)
        elif k == "file_id" and v is not None:
            setattr(u, "emp_file_id", uuid.UUID(v) if v else None)
        elif v is not None:
            setattr(u, k, v)
    u.updated_at = _now()
    await db.commit()
    await db.refresh(u)
    await audit_log(db, current_user, "employee_update", "user", u.id, u.username, request=request)
    return {"ok": True}


# ── Resumes ──

@router.get("/resumes")
async def list_resumes(
    status: str = "",
    limit: int = 50,
    offset: int = 0,
    db: AsyncSession = Depends(get_db),
    user: User = Depends(get_current_user),
):
    query = select(Resume).order_by(Resume.updated_at.desc())
    if user.role != "admin":
        if user.department_id:
            query = query.where(Resume.department_id == user.department_id)
        else:
            query = query.where(Resume.created_by == user.id)
    if status:
        query = query.where(Resume.status == status)
    result = await db.execute(query.offset(offset).limit(limit))
    return {"items": [_resume_row(r) for r in result.scalars().all()]}


@router.post("/resumes")
async def create_resume(
    body: ResumeCreate,
    request: Request = None,
    db: AsyncSession = Depends(get_db),
    user: User = Depends(get_current_user),
):
    file_id = uuid.UUID(body.file_id) if body.file_id else None
    r = Resume(
        name=body.name,
        content=body.content,
        file_id=file_id,
        department_id=user.department_id,
        created_by=user.id,
    )
    db.add(r)
    await db.commit()
    await db.refresh(r)
    await audit_log(db, user, "resume_create", "resume", r.id, r.name, request=request)
    await es_index(str(r.id), "resumes", r.name, r.content or "", extra=r.status or "", department_id=str(user.department_id) if user.department_id else None)
    return _resume_row(r)


@router.post("/resumes/upload")
async def upload_resume(
    file: UploadFile = FastAPIFile(...),
    name: str = Form(""),
    request: Request = None,
    db: AsyncSession = Depends(get_db),
    user: User = Depends(get_current_user),
):
    content_bytes = await file.read()
    storage_path = f"resumes/{uuid.uuid4()}/{file.filename}"

    await upload_file(storage_path, content_bytes, file.content_type or "application/pdf")

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

    text_content = await extract_text(content_bytes, file.filename)

    r = Resume(
        name=name.strip() or file.filename,
        content=text_content or "",
        file_id=file_record.id,
        department_id=user.department_id,
        created_by=user.id,
    )
    db.add(r)
    await db.commit()
    await db.refresh(r)
    await audit_log(db, user, "resume_upload", "resume", r.id, r.name, request=request)
    await es_index(str(r.id), "resumes", r.name, r.content or "", extra=r.status or "", department_id=str(user.department_id) if user.department_id else None)
    return _resume_row(r)


@router.get("/resumes/{resume_id}")
async def get_resume(
    resume_id: str,
    db: AsyncSession = Depends(get_db),
    user: User = Depends(get_current_user),
):
    result = await db.execute(select(Resume).where(Resume.id == resume_id))
    r = result.scalar_one_or_none()
    if not r:
        raise HTTPException(404, "简历不存在")
    return _resume_row(r)


@router.put("/resumes/{resume_id}")
async def update_resume(
    resume_id: str,
    body: ResumeUpdate,
    request: Request = None,
    db: AsyncSession = Depends(get_db),
    user: User = Depends(get_current_user),
):
    result = await db.execute(select(Resume).where(Resume.id == resume_id))
    r = result.scalar_one_or_none()
    if not r:
        raise HTTPException(404, "简历不存在")
    for k, v in body.model_dump(exclude_none=True).items():
        setattr(r, k, v)
    r.updated_at = _now()
    await db.commit()
    await db.refresh(r)
    await audit_log(db, user, "resume_update", "resume", r.id, r.name, request=request)
    await es_index(str(r.id), "resumes", r.name, r.content or "", extra=r.status or "", department_id=str(user.department_id) if user.department_id else None)
    return _resume_row(r)


@router.delete("/resumes/{resume_id}")
async def delete_resume(
    resume_id: str,
    request: Request = None,
    db: AsyncSession = Depends(get_db),
    user: User = Depends(get_current_user),
):
    result = await db.execute(select(Resume).where(Resume.id == resume_id))
    r = result.scalar_one_or_none()
    if not r:
        raise HTTPException(404, "简历不存在")
    await db.delete(r)
    await db.commit()
    await audit_log(db, user, "resume_delete", "resume", r.id, r.name, request=request)
    await es_delete(str(r.id), "resumes")
    return {"ok": True}


@router.post("/resumes/{resume_id}/match")
async def match_resume(
    resume_id: str,
    request: Request = None,
    db: AsyncSession = Depends(get_db),
    user: User = Depends(get_current_user),
):
    result = await db.execute(select(Resume).where(Resume.id == resume_id))
    r = result.scalar_one_or_none()
    if not r:
        raise HTTPException(404, "简历不存在")
    if not r.content:
        raise HTTPException(400, "简历无内容可分析")

    prompt = f"""请分析以下简历，返回严格JSON格式（不要Markdown，不要```代码块）。

简历内容:
{r.content}

请返回如下JSON结构:
{{
  "scores": {{
    "专业技能": 8,
    "工作经验": 7,
    "项目经验": 8,
    "教育背景": 6,
    "沟通协作": 7,
    "学习能力": 7
  }},
  "strengths": "候选人的核心优势描述，2-3句话",
  "department_matches": [
    {{"department": "技术部", "score": 85, "reason": "匹配理由一句话"}},
    {{"department": "市场部", "score": 60, "reason": "匹配理由一句话"}}
  ],
  "recommended_salary": "15k-20k/月",
  "summary": "综合评价2-3句话，包含总体评分（0-100分）"
}}

注意:
- scores中每项1-10分
- department_matches列出2-3个最匹配的部门，score为0-100匹配度
- recommended_salary基于经验和能力给出薪资建议
- 只返回JSON，不要其他内容"""

    llm = get_llm()
    resp = await llm.generate(system_prompt="你是一个专业的HR招聘顾问。请严格按JSON格式返回分析结果，不要任何Markdown标记。", user_prompt=prompt)
    result_text = resp.content.strip()
    if result_text.startswith("```"):
        result_text = result_text.split("\n", 1)[-1].rsplit("\n```", 1)[0] if "\n```" in result_text else result_text.split("```", 1)[-1].rsplit("```", 1)[0]

    analysis = None
    score = 50.0
    try:
        import json
        analysis = json.loads(result_text)
        scores = analysis.get("scores", {})
        if scores:
            score = sum(scores.values()) / len(scores) * 10.0
        summary = analysis.get("summary", "")
        import re
        nums = re.findall(r"(\d+)", summary)
        if nums:
            score = float(nums[0]) if 0 < float(nums[0]) <= 100 else score
    except Exception:
        analysis = {"scores": {}, "strengths": "", "department_matches": [], "recommended_salary": "", "summary": result_text}

    r.match_score = score
    r.match_result = result_text
    r.status = "reviewed"
    r.updated_at = _now()
    await db.commit()
    await db.refresh(r)
    await audit_log(db, user, "resume_match", "resume", r.id, r.name, detail=f"score={score}", request=request)
    result_dict = _resume_row(r)
    result_dict["analysis"] = analysis
    return result_dict


# ── Approvals ──

async def _load_steps(approval_id: uuid.UUID, db: AsyncSession) -> list[ApprovalStep]:
    result = await db.execute(
        select(ApprovalStep).where(ApprovalStep.approval_id == approval_id).order_by(ApprovalStep.level)
    )
    return list(result.scalars().all())


@router.get("/approvals")
async def list_approvals(
    approval_type: str = "",
    status: str = "",
    limit: int = 50,
    offset: int = 0,
    db: AsyncSession = Depends(get_db),
    user: User = Depends(get_current_user),
):
    query = select(Approval).order_by(Approval.updated_at.desc())
    if user.role != "admin":
        if user.department_id:
            query = query.where(Approval.department_id == user.department_id)
        else:
            query = query.where(
                (Approval.applicant_id == user.id) | (Approval.approver_id == user.id)
            )
    if approval_type:
        query = query.where(Approval.approval_type == approval_type)
    if status:
        query = query.where(Approval.status == status)
    result = await db.execute(query.offset(offset).limit(limit))
    approvals = result.scalars().all()
    items = []
    for a in approvals:
        steps = await _load_steps(a.id, db)
        items.append(_approval_row(a, steps))
    return {"items": items}


@router.post("/approvals")
async def create_approval(
    body: ApprovalCreate,
    request: Request = None,
    db: AsyncSession = Depends(get_db),
    user: User = Depends(get_current_user),
):
    applicant_id = uuid.UUID(body.applicant_id) if body.applicant_id else user.id
    a = Approval(
        approval_type=body.approval_type,
        applicant_id=applicant_id,
        content=body.content,
        department_id=user.department_id,
    )
    db.add(a)
    await db.flush()

    num_levels = _WORKFLOW_LEVELS.get(body.approval_type, 1)
    for level in range(1, num_levels + 1):
        db.add(ApprovalStep(approval_id=a.id, level=level))

    await db.commit()
    await db.refresh(a)
    steps = await _load_steps(a.id, db)
    await audit_log(db, user, "approval_create", "approval", a.id, a.approval_type, request=request)
    return _approval_row(a, steps)


@router.get("/approvals/{approval_id}")
async def get_approval(
    approval_id: str,
    db: AsyncSession = Depends(get_db),
    user: User = Depends(get_current_user),
):
    result = await db.execute(select(Approval).where(Approval.id == approval_id))
    a = result.scalar_one_or_none()
    if not a:
        raise HTTPException(404, "审批不存在")
    steps = await _load_steps(a.id, db)
    return _approval_row(a, steps)


@router.put("/approvals/{approval_id}")
async def handle_approval(
    approval_id: str,
    body: ApprovalAction,
    request: Request = None,
    db: AsyncSession = Depends(get_db),
    user: User = Depends(get_current_user),
):
    """Legacy endpoint — approves/rejects the first pending step."""
    result = await db.execute(select(Approval).where(Approval.id == approval_id))
    a = result.scalar_one_or_none()
    if not a:
        raise HTTPException(404, "审批不存在")
    if body.status not in ("approved", "rejected"):
        raise HTTPException(400, "状态必须是 approved 或 rejected")

    if a.status != "pending":
        raise HTTPException(400, "审批已处理，无法重复操作")

    steps = await _load_steps(a.id, db)
    current_step = next((s for s in steps if s.status == "pending"), None)
    if not current_step:
        raise HTTPException(400, "没有待处理的审批步骤")

    current_step.status = body.status
    current_step.comment = body.comment
    current_step.approver_id = user.id
    current_step.updated_at = _now()

    if body.status == "rejected":
        a.status = "rejected"
    else:
        next_step = next((s for s in steps if s.level > current_step.level and s.status == "pending"), None)
        if next_step is None:
            a.status = "approved"

    a.approver_id = user.id
    a.comment = body.comment
    a.updated_at = _now()
    await db.commit()
    await db.refresh(a)
    steps = await _load_steps(a.id, db)
    await audit_log(db, user, f"approval_{body.status}", "approval", a.id, a.approval_type, request=request)
    return _approval_row(a, steps)


@router.put("/approvals/{approval_id}/steps/{step_id}")
async def handle_approval_step(
    approval_id: str,
    step_id: str,
    body: ApprovalStepAction,
    request: Request = None,
    db: AsyncSession = Depends(get_db),
    user: User = Depends(get_current_user),
):
    """Approve or reject a specific step in a multi-level approval."""
    result = await db.execute(select(Approval).where(Approval.id == approval_id))
    a = result.scalar_one_or_none()
    if not a:
        raise HTTPException(404, "审批不存在")
    if a.status != "pending":
        raise HTTPException(400, "审批已处理，无法重复操作")
    if body.status not in ("approved", "rejected"):
        raise HTTPException(400, "状态必须是 approved 或 rejected")

    step_result = await db.execute(
        select(ApprovalStep).where(ApprovalStep.id == step_id, ApprovalStep.approval_id == uuid.UUID(approval_id))
    )
    step = step_result.scalar_one_or_none()
    if not step:
        raise HTTPException(404, "审批步骤不存在")
    if step.status != "pending":
        raise HTTPException(400, "该步骤已处理")

    steps = await _load_steps(a.id, db)
    prev_steps = [s for s in steps if s.level < step.level]
    if any(s.status != "approved" for s in prev_steps):
        raise HTTPException(400, "请先完成前置步骤的审批")

    step.status = body.status
    step.comment = body.comment
    step.approver_id = user.id
    step.updated_at = _now()

    if body.status == "rejected":
        a.status = "rejected"
    else:
        remaining = [s for s in steps if s.level > step.level and s.status == "pending"]
        if not remaining:
            a.status = "approved"

    a.approver_id = user.id
    a.comment = body.comment
    a.updated_at = _now()
    await db.commit()
    await db.refresh(a)
    steps = await _load_steps(a.id, db)
    await audit_log(db, user, f"approval_step_{body.status}", "approval_step", step.id, body.comment, request=request)
    return _approval_row(a, steps)


@router.delete("/approvals/{approval_id}")
async def delete_approval(
    approval_id: str,
    request: Request = None,
    db: AsyncSession = Depends(get_db),
    user: User = Depends(get_current_user),
):
    result = await db.execute(select(Approval).where(Approval.id == approval_id))
    a = result.scalar_one_or_none()
    if not a:
        raise HTTPException(404, "审批不存在")
    await db.delete(a)
    await db.commit()
    await audit_log(db, user, "approval_delete", "approval", a.id, a.approval_type, request=request)
    return {"ok": True}


# ── Interviews ──

@router.get("/interviews")
async def list_interviews(
    status: str = "",
    from_date: str = "",
    to_date: str = "",
    offset: int = 0,
    limit: int = 50,
    db: AsyncSession = Depends(get_db),
    user: User = Depends(get_current_user),
):
    query = select(Interview)
    if user.role != "admin":
        query = query.where(Interview.department_id == user.department_id)
    if status:
        query = query.where(Interview.status == status)
    if from_date:
        query = query.where(Interview.scheduled_at >= datetime.fromisoformat(from_date))
    if to_date:
        query = query.where(Interview.scheduled_at <= datetime.fromisoformat(to_date))
    query = query.order_by(Interview.scheduled_at.is_(None), Interview.scheduled_at.asc(), Interview.created_at.desc())
    result = await db.execute(query.offset(offset).limit(limit))
    return {"items": [_interview_row(i) for i in result.scalars().all()]}


@router.post("/interviews")
async def create_interview(
    body: InterviewCreate,
    request: Request = None,
    db: AsyncSession = Depends(get_db),
    user: User = Depends(get_current_user),
):
    scheduled = datetime.fromisoformat(body.scheduled_at) if body.scheduled_at else None
    interviewer_id = uuid.UUID(body.interviewer_id) if body.interviewer_id else None
    i = Interview(
        candidate_name=body.candidate_name,
        position=body.position,
        scheduled_at=scheduled,
        duration_minutes=body.duration_minutes,
        interviewer_id=interviewer_id,
        notes=body.notes,
        department_id=user.department_id,
        created_by=user.id,
    )
    db.add(i)
    await db.commit()
    await db.refresh(i)
    await audit_log(db, user, "interview_create", "interview", i.id, i.candidate_name, request=request)
    return _interview_row(i)


@router.get("/interviews/{interview_id}")
async def get_interview(
    interview_id: str,
    db: AsyncSession = Depends(get_db),
    user: User = Depends(get_current_user),
):
    result = await db.execute(select(Interview).where(Interview.id == interview_id))
    i = result.scalar_one_or_none()
    if not i:
        raise HTTPException(404, "面试不存在")
    return _interview_row(i)


@router.put("/interviews/{interview_id}")
async def update_interview(
    interview_id: str,
    body: InterviewUpdate,
    request: Request = None,
    db: AsyncSession = Depends(get_db),
    user: User = Depends(get_current_user),
):
    result = await db.execute(select(Interview).where(Interview.id == interview_id))
    i = result.scalar_one_or_none()
    if not i:
        raise HTTPException(404, "面试不存在")
    for k, v in body.model_dump(exclude_none=True).items():
        if k == "scheduled_at" and v is not None:
            setattr(i, k, datetime.fromisoformat(v) if v else None)
        elif k == "interviewer_id" and v is not None:
            setattr(i, k, uuid.UUID(v) if v else None)
        elif v is not None:
            setattr(i, k, v)
    i.updated_at = _now()
    await db.commit()
    await db.refresh(i)
    await audit_log(db, user, "interview_update", "interview", i.id, i.candidate_name, request=request)
    return _interview_row(i)


@router.delete("/interviews/{interview_id}")
async def delete_interview(
    interview_id: str,
    request: Request = None,
    db: AsyncSession = Depends(get_db),
    user: User = Depends(get_current_user),
):
    result = await db.execute(select(Interview).where(Interview.id == interview_id))
    i = result.scalar_one_or_none()
    if not i:
        raise HTTPException(404, "面试不存在")
    await db.delete(i)
    await db.commit()
    await audit_log(db, user, "interview_delete", "interview", i.id, i.candidate_name, request=request)
    return {"ok": True}
