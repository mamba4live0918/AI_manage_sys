import uuid
from datetime import datetime, timedelta, timezone

from fastapi import APIRouter, Depends, Form, HTTPException, Request, UploadFile, File as FastAPIFile
from pydantic import BaseModel
from sqlalchemy import select, func
from sqlalchemy.ext.asyncio import AsyncSession

from app.database import get_db
from app.models import User, File, Resume, Approval, ApprovalStep, Interview, AuditLog
from app.security import get_current_user, require_module
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


def _approval_row(a: Approval, steps: list[ApprovalStep] | None = None,
                   applicant: User | None = None) -> dict:
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
    if applicant:
        row["applicant"] = {
            "username": applicant.username,
            "email": applicant.email,
            "department": applicant.department or "",
            "position": applicant.position or "",
            "emp_status": applicant.emp_status or "active",
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


# ── Employee Files (multiple files per employee) ──

from app.models import EmployeeFile  # noqa: E402


@router.get("/users/{user_id}/files")
async def list_employee_files(
    user_id: str,
    db: AsyncSession = Depends(get_db),
    user: User = Depends(get_current_user),
):
    result = await db.execute(
        select(EmployeeFile).where(EmployeeFile.user_id == user_id).order_by(EmployeeFile.created_at.desc())
    )
    items = result.scalars().all()
    return {
        "items": [
            {
                "id": str(f.id),
                "user_id": str(f.user_id),
                "file_id": str(f.file_id),
                "file_type": f.file_type,
                "name": f.name,
                "created_at": f.created_at.isoformat() if f.created_at else None,
            }
            for f in items
        ]
    }


@router.post("/users/{user_id}/files")
async def add_employee_file(
    user_id: str,
    file_id: str = Form(...),
    file_type: str = Form("other"),
    name: str = Form(""),
    db: AsyncSession = Depends(get_db),
    user: User = Depends(get_current_user),
):
    if user.role != "admin":
        raise HTTPException(403, "仅管理员可操作")
    ef = EmployeeFile(
        user_id=uuid.UUID(user_id),
        file_id=uuid.UUID(file_id),
        file_type=file_type,
        name=name,
    )
    db.add(ef)
    await db.commit()
    return {"ok": True, "id": str(ef.id)}


@router.delete("/users/{user_id}/files/{ef_id}")
async def remove_employee_file(
    user_id: str,
    ef_id: str,
    db: AsyncSession = Depends(get_db),
    user: User = Depends(get_current_user),
):
    if user.role != "admin":
        raise HTTPException(403, "仅管理员可操作")
    result = await db.execute(
        select(EmployeeFile).where(EmployeeFile.id == uuid.UUID(ef_id), EmployeeFile.user_id == uuid.UUID(user_id))
    )
    ef = result.scalar_one_or_none()
    if not ef:
        raise HTTPException(404, "文件关联不存在")
    await db.delete(ef)
    await db.commit()
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

    prompt = f"""请严格分析以下简历，返回JSON格式（不要Markdown，不要```代码块）。

简历内容:
{r.content}

评分标准（1-10分，正态分布，大多数人落在4-7分）:
- 1-3分：初级 — 缺乏相关经验或技能，仅满足最低要求
- 4-6分：合格 — 具备基本能力和一定经验，能满足岗位需求
- 7-8分：优秀 — 经验丰富、有突出成果，超出多数同类候选人
- 9-10分：卓越 — 行业顶尖水平，有显著成就和影响力（极少使用）

请返回如下JSON结构，每项评分必须附带简短证据:
{{
  "scores": {{
    "专业技能": {{"score": 5, "evidence": "掌握Python/Java，但无大规模分布式系统经验"}},
    "工作经验": {{"score": 4, "evidence": "3年工作经验，无团队管理经历"}},
    "项目经验": {{"score": 6, "evidence": "参与过2个中型项目，独立负责过核心模块"}},
    "教育背景": {{"score": 5, "evidence": "本科计算机专业，无知名院校背景"}},
    "沟通协作": {{"score": 5, "evidence": "有跨部门协作经验，但未担任过项目负责人"}},
    "学习能力": {{"score": 5, "evidence": "自学过新技术但无公开发表或开源贡献"}}
  }},
  "strengths": "候选人的核心优势，2-3句话，要具体不空泛",
  "weaknesses": "候选人的明显短板或风险点，2-3句话",
  "summary": "综合评价2-3句话，概述候选人整体匹配度与核心结论",
  "department_matches": [
    {{"department": "技术部", "score": 65, "reason": "技术栈匹配度较高，但架构能力不足"}},
    {{"department": "市场部", "score": 35, "reason": "无市场相关经验"}}
  ],
  "recommended_salary": "基于市场行情和候选人水平的薪资建议（如'12k-18k/月'）",
  "overall_score": 55
}}

注意:
- scores中每项评分必须附带evidence，说明评分依据
- 整体评分请客观，不要随便给高分
- overall_score为0-100的综合评分，要与各维度评分一致（大致为各维度均分×10）
- department_matches列出2-3个部门，score为0-100匹配度，70以上才算匹配
- recommended_salary要实事求是，不要虚高
- 只返回JSON，不要其他内容"""

    llm = get_llm()
    resp = await llm.generate(system_prompt="你是一个严谨专业的HR招聘顾问。请客观评估，依据简历事实打分，避免虚高。多数候选人应在4-7分区间。严格按JSON格式返回分析结果，不要Markdown标记。", user_prompt=prompt)
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
            score_values = []
            for v in scores.values():
                if isinstance(v, dict):
                    score_values.append(v.get("score", 5))
                elif isinstance(v, (int, float)):
                    score_values.append(v)
            if score_values:
                score = sum(score_values) / len(score_values) * 10.0
        if "overall_score" in analysis:
            overall = analysis["overall_score"]
            if isinstance(overall, (int, float)) and 0 < overall <= 100:
                score = float(overall)
        elif "summary" in analysis:
            import re
            nums = re.findall(r"(\d+)", analysis["summary"])
            if nums:
                s = float(nums[0])
                if 0 < s <= 100:
                    score = s
    except Exception:
        analysis = {"scores": {}, "strengths": "", "weaknesses": "", "department_matches": [], "recommended_salary": "", "summary": result_text}

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
        # HR department members can see all approvals
        is_hr = False
        if user.department_id:
            from app.models import Department
            dept = await db.get(Department, user.department_id)
            if dept and "hr" in (dept.accessible_modules or []):
                is_hr = True
        if "hr" in (user.extra_modules or []):
            is_hr = True
        if not is_hr:
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

    applicant_ids = [a.applicant_id for a in approvals if a.applicant_id]
    applicant_map: dict[uuid.UUID, User] = {}
    if applicant_ids:
        user_result = await db.execute(select(User).where(User.id.in_(applicant_ids)))
        applicant_map = {u.id: u for u in user_result.scalars().all()}

    items = []
    for a in approvals:
        items.append(_approval_row(a, None, applicant=applicant_map.get(a.applicant_id)))
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
    await db.commit()
    await db.refresh(a)
    await audit_log(db, user, "approval_create", "approval", a.id, a.approval_type, request=request)
    return _approval_row(a, None)


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
    result = await db.execute(select(Approval).where(Approval.id == approval_id))
    a = result.scalar_one_or_none()
    if not a:
        raise HTTPException(404, "审批不存在")
    if body.status not in ("approved", "rejected"):
        raise HTTPException(400, "状态必须是 approved 或 rejected")

    a.status = body.status
    a.comment = body.comment
    a.approver_id = user.id
    a.updated_at = _now()
    await db.commit()
    await db.refresh(a)
    await audit_log(db, user, f"approval_{body.status}", "approval", a.id, a.approval_type, request=request)
    return _approval_row(a, None)


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


# ── Dashboard ──

@router.get("/dashboard")
async def get_hr_dashboard(
    db: AsyncSession = Depends(get_db),
    user: User = Depends(get_current_user),
    _m: User = Depends(require_module("hr")),
):

    dept_filter = []
    if user.role != "admin" and user.department_id:
        dept_filter.append(User.department_id == user.department_id)

    # Employee stats
    emp_base = select(User).where(User.role == "general")
    for f in dept_filter:
        emp_base = emp_base.where(f)

    emp_result = await db.execute(emp_base)
    employees = emp_result.scalars().all()
    total = len(employees)
    active = sum(1 for e in employees if e.emp_status == "active")
    probation = sum(1 for e in employees if e.emp_status == "probation")
    resigned = sum(1 for e in employees if e.emp_status == "resigned")
    this_month = sum(1 for e in employees if e.hire_date and e.hire_date.month == _now().month and e.hire_date.year == _now().year)

    dept_counts: dict[str, int] = {}
    for e in employees:
        d = e.department or "未分配"
        dept_counts[d] = dept_counts.get(d, 0) + 1
    employees_by_department = [{"department": k, "count": v} for k, v in dept_counts.items()]

    employees_by_status = [
        {"status": "active", "count": active},
        {"status": "probation", "count": probation},
        {"status": "resigned", "count": resigned},
    ]

    # Resume stats
    resume_base = select(Resume)
    if user.role != "admin" and user.department_id:
        resume_base = resume_base.where(Resume.department_id == user.department_id)
    resume_result = await db.execute(resume_base)
    resumes = resume_result.scalars().all()

    pending_resumes = sum(1 for r in resumes if r.status == "new")
    today_resumes = sum(1 for r in resumes if r.created_at and r.created_at.date() == _now().date())

    resume_status_counts: dict[str, int] = {}
    for r in resumes:
        s = r.status or "new"
        resume_status_counts[s] = resume_status_counts.get(s, 0) + 1
    resumes_by_status = [{"status": k, "count": v} for k, v in resume_status_counts.items()]

    # Approval stats
    approval_base = select(Approval)
    if user.role != "admin" and user.department_id:
        approval_base = approval_base.where(Approval.department_id == user.department_id)
    approval_result = await db.execute(approval_base)
    approvals = approval_result.scalars().all()

    pending_approvals = sum(1 for a in approvals if a.status == "pending")
    approval_type_counts: dict[str, int] = {}
    for a in approvals:
        approval_type_counts[a.approval_type] = approval_type_counts.get(a.approval_type, 0) + 1
    approvals_by_type = [{"type": k, "count": v} for k, v in approval_type_counts.items()]

    # Interview stats
    interview_base = select(Interview)
    if user.role != "admin" and user.department_id:
        interview_base = interview_base.where(Interview.department_id == user.department_id)
    interview_result = await db.execute(interview_base)
    interviews = interview_result.scalars().all()

    today_date = _now().date()
    today_interviews = sum(1 for i in interviews if i.scheduled_at and i.scheduled_at.date() == today_date)
    week_start = today_date - timedelta(days=today_date.weekday())
    week_end = week_start + timedelta(days=6)
    week_interviews = sum(1 for i in interviews if i.scheduled_at and week_start <= i.scheduled_at.date() <= week_end)

    upcoming = sorted(
        [i for i in interviews if i.scheduled_at and i.scheduled_at >= _now()],
        key=lambda x: x.scheduled_at,
    )[:5]
    upcoming_interviews = [_interview_row(i) for i in upcoming]

    # Recent HR activities
    hr_actions = [
        "resume_create", "resume_upload", "resume_match", "resume_update", "resume_delete",
        "approval_create", "approval_approved", "approval_rejected",
        "approval_step_approved", "approval_step_rejected",
        "interview_create", "interview_update", "interview_delete",
        "employee_update",
    ]
    audit_query = select(AuditLog).where(AuditLog.action.in_(hr_actions)).order_by(AuditLog.created_at.desc()).limit(20)
    if user.role != "admin" and user.department_id:
        audit_query = audit_query.where(AuditLog.user_id.in_(
            select(User.id).where(User.department_id == user.department_id)
        ))
    audit_result = await db.execute(audit_query)
    recent_activities = []
    for a in audit_result.scalars().all():
        recent_activities.append({
            "id": str(a.id),
            "username": a.username,
            "action": a.action,
            "resource_type": a.resource_type,
            "resource_name": a.resource_name,
            "detail": a.detail,
            "created_at": a.created_at.isoformat() if a.created_at else None,
        })

    return {
        "total_employees": total,
        "active_employees": active,
        "new_hires_this_month": this_month,
        "employees_by_department": employees_by_department,
        "employees_by_status": employees_by_status,
        "pending_resumes": pending_resumes,
        "new_resumes_today": today_resumes,
        "resumes_by_status": resumes_by_status,
        "pending_approvals": pending_approvals,
        "approvals_by_type": approvals_by_type,
        "today_interviews": today_interviews,
        "week_interviews": week_interviews,
        "upcoming_interviews": upcoming_interviews,
        "recent_activities": recent_activities,
    }
