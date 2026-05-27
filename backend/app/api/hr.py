import uuid
from datetime import datetime, timezone

from fastapi import APIRouter, Depends, Form, HTTPException, Request, UploadFile, File as FastAPIFile
from pydantic import BaseModel
from sqlalchemy import select, func
from sqlalchemy.ext.asyncio import AsyncSession

from app.database import get_db
from app.models import User, Employee, File, Resume, Approval
from app.security import get_current_user
from app.services.llm.router import get_llm
from app.services.audit import log as audit_log
from app.services.file_extractor import extract_text
from app.services.storage import upload_file

router = APIRouter(prefix="/hr", tags=["hr"])


def _now():
    return datetime.now(timezone.utc)


# ── Pydantic Schemas ──

class EmployeeCreate(BaseModel):
    name: str
    position: str = ""
    hire_date: str | None = None
    status: str = "active"
    phone: str = ""
    email: str = ""
    notes: str = ""


class EmployeeUpdate(BaseModel):
    name: str | None = None
    position: str | None = None
    hire_date: str | None = None
    status: str | None = None
    phone: str | None = None
    email: str | None = None
    notes: str | None = None


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


# ── Row Serializers ──

def _employee_row(e: Employee) -> dict:
    return {
        "id": str(e.id),
        "name": e.name,
        "position": e.position,
        "department_id": str(e.department_id) if e.department_id else None,
        "hire_date": e.hire_date.isoformat() if e.hire_date else None,
        "status": e.status,
        "phone": e.phone,
        "email": e.email,
        "notes": e.notes,
        "created_by": str(e.created_by) if e.created_by else None,
        "created_at": e.created_at.isoformat() if e.created_at else None,
        "updated_at": e.updated_at.isoformat() if e.updated_at else None,
    }


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


def _approval_row(a: Approval) -> dict:
    return {
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


# ── Employees ──

@router.get("/employees")
async def list_employees(
    status: str = "",
    limit: int = 50,
    offset: int = 0,
    db: AsyncSession = Depends(get_db),
    user: User = Depends(get_current_user),
):
    query = select(Employee).order_by(Employee.updated_at.desc())
    if user.role != "admin":
        if user.department_id:
            query = query.where(Employee.department_id == user.department_id)
        else:
            query = query.where(Employee.created_by == user.id)
    if status:
        query = query.where(Employee.status == status)
    result = await db.execute(query.offset(offset).limit(limit))
    return {"items": [_employee_row(e) for e in result.scalars().all()]}


@router.post("/employees")
async def create_employee(
    body: EmployeeCreate,
    request: Request = None,
    db: AsyncSession = Depends(get_db),
    user: User = Depends(get_current_user),
):
    hire_date = datetime.fromisoformat(body.hire_date) if body.hire_date else None
    e = Employee(
        name=body.name,
        position=body.position,
        department_id=user.department_id,
        hire_date=hire_date,
        status=body.status,
        phone=body.phone,
        email=body.email,
        notes=body.notes,
        created_by=user.id,
    )
    db.add(e)
    await db.commit()
    await db.refresh(e)
    await audit_log(db, user, "employee_create", "employee", e.id, e.name, request=request)
    return _employee_row(e)


@router.get("/employees/{employee_id}")
async def get_employee(
    employee_id: str,
    db: AsyncSession = Depends(get_db),
    user: User = Depends(get_current_user),
):
    result = await db.execute(select(Employee).where(Employee.id == employee_id))
    e = result.scalar_one_or_none()
    if not e:
        raise HTTPException(404, "员工不存在")
    return _employee_row(e)


@router.put("/employees/{employee_id}")
async def update_employee(
    employee_id: str,
    body: EmployeeUpdate,
    request: Request = None,
    db: AsyncSession = Depends(get_db),
    user: User = Depends(get_current_user),
):
    result = await db.execute(select(Employee).where(Employee.id == employee_id))
    e = result.scalar_one_or_none()
    if not e:
        raise HTTPException(404, "员工不存在")
    for k, v in body.model_dump(exclude_none=True).items():
        if k == "hire_date" and v is not None:
            setattr(e, k, datetime.fromisoformat(v) if v else None)
        elif v is not None:
            setattr(e, k, v)
    e.updated_at = _now()
    await db.commit()
    await db.refresh(e)
    await audit_log(db, user, "employee_update", "employee", e.id, e.name, request=request)
    return _employee_row(e)


@router.delete("/employees/{employee_id}")
async def delete_employee(
    employee_id: str,
    request: Request = None,
    db: AsyncSession = Depends(get_db),
    user: User = Depends(get_current_user),
):
    result = await db.execute(select(Employee).where(Employee.id == employee_id))
    e = result.scalar_one_or_none()
    if not e:
        raise HTTPException(404, "员工不存在")
    await db.delete(e)
    await db.commit()
    await audit_log(db, user, "employee_delete", "employee", e.id, e.name, request=request)
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

    prompt = f"""请分析以下简历，评估候选人的综合能力。

简历内容:
{r.content}

请从以下维度评估（每项1-10分）并给出总结：
1. 专业技能匹配度
2. 工作经验年限
3. 项目经验质量
4. 教育背景
5. 综合推荐度

最后给出一个综合评分（0-100分）和推荐意见。用Markdown格式输出。"""

    llm = get_llm()
    resp = await llm.generate(system_prompt="你是一个专业的HR招聘顾问，请对简历进行专业分析评估。", user_prompt=prompt)
    result_text = resp.content

    score = 50.0
    for line in result_text.split("\n"):
        if "综合评分" in line or "总分" in line:
            import re
            nums = re.findall(r"(\d+)", line)
            if nums:
                score = float(nums[0])

    r.match_score = score
    r.match_result = result_text
    r.status = "reviewed"
    r.updated_at = _now()
    await db.commit()
    await db.refresh(r)
    await audit_log(db, user, "resume_match", "resume", r.id, r.name, detail=f"score={score}", request=request)
    return _resume_row(r)


# ── Approvals ──

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
    return {"items": [_approval_row(a) for a in result.scalars().all()]}


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
    return _approval_row(a)


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
    return _approval_row(a)


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
