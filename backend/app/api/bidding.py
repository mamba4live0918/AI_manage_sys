import difflib
import json
import uuid
from datetime import datetime, timezone

from fastapi import APIRouter, Depends, HTTPException, Request, UploadFile, File as FastAPIFile
from pydantic import BaseModel
from sqlalchemy import select, func
from sqlalchemy.ext.asyncio import AsyncSession

from app.database import get_db
from app.models import (
    User, ContractTemplate, Contract, ContractVersion,
    BiddingKnowledgeDir, BiddingKnowledgeDoc,
    BiddingProcess, Supplier, Instructor, File, QAChatRecord,
)
from app.security import get_current_user
from app.services.llm.router import get_llm
from app.services.llm.base import LLMConfig
from app.services.audit import log as audit_log
from app.services.file_extractor import extract_text
from app.services.storage import upload_file, get_presigned_url, delete_file
from app.services.search import index_document as es_index, delete_document as es_delete

router = APIRouter(prefix="/bidding", tags=["bidding"])


def _now():
    return datetime.now(timezone.utc)


# ── Pydantic Schemas ──

class TemplateCreate(BaseModel):
    name: str
    type: str = "service"
    content: str = ""
    system_prompt: str = ""


class TemplateUpdate(BaseModel):
    name: str | None = None
    type: str | None = None
    content: str | None = None
    system_prompt: str | None = None


class ContractGenerateRequest(BaseModel):
    template_id: str | None = None
    title: str
    counterparty: str = ""
    variables: dict[str, str] = {}


class ContractUpdate(BaseModel):
    title: str | None = None
    counterparty: str | None = None
    status: str | None = None
    signed_at: str | None = None
    expires_at: str | None = None


class KnowledgeDirCreate(BaseModel):
    name: str
    parent_id: str | None = None


class KnowledgeDocCreate(BaseModel):
    dir_id: str | None = None
    title: str
    content: str = ""
    tags: list[str] = []


class KnowledgeDocUpdate(BaseModel):
    dir_id: str | None = None
    title: str | None = None
    content: str | None = None
    tags: list[str] | None = None


class ProcessCreate(BaseModel):
    project_name: str
    stage: str = "preparation"
    deadline: str | None = None
    notes: str = ""


class ProcessUpdate(BaseModel):
    project_name: str | None = None
    stage: str | None = None
    deadline: str | None = None
    notes: str | None = None


class SupplierCreate(BaseModel):
    name: str
    type: str = "company"
    contact_person: str = ""
    contact_phone: str = ""
    contact_email: str = ""
    tags: list[str] = []
    expertise: list[str] = []
    rating: float = 0.0
    notes: str = ""


class SupplierUpdate(BaseModel):
    name: str | None = None
    type: str | None = None
    contact_person: str | None = None
    contact_phone: str | None = None
    contact_email: str | None = None
    tags: list[str] | None = None
    expertise: list[str] | None = None
    rating: float | None = None
    status: str | None = None
    notes: str | None = None


class InstructorCreate(BaseModel):
    name: str
    supplier_id: str | None = None
    expertise: list[str] = []
    tags: list[str] = []
    qualifications: list[str] = []
    experience_years: int = 0
    courses_taught: list[str] = []
    rating: float = 0.0
    notes: str = ""


class InstructorUpdate(BaseModel):
    name: str | None = None
    supplier_id: str | None = None
    expertise: list[str] | None = None
    tags: list[str] | None = None
    qualifications: list[str] | None = None
    experience_years: int | None = None
    courses_taught: list[str] | None = None
    rating: float | None = None
    status: str | None = None
    notes: str | None = None


class MatchCourseRequest(BaseModel):
    course_name: str = ""
    requirements: str = ""


# ── Row Serializers ──

def _template_row(t: ContractTemplate) -> dict:
    return {
        "id": str(t.id),
        "name": t.name,
        "type": t.type,
        "content": t.content,
        "system_prompt": t.system_prompt,
        "department_id": str(t.department_id) if t.department_id else None,
        "created_by": str(t.created_by) if t.created_by else None,
        "created_at": t.created_at.isoformat() if t.created_at else None,
        "updated_at": t.updated_at.isoformat() if t.updated_at else None,
    }


def _contract_row(c: Contract) -> dict:
    return {
        "id": str(c.id),
        "title": c.title,
        "template_id": str(c.template_id) if c.template_id else None,
        "counterparty": c.counterparty,
        "status": c.status,
        "current_version": c.current_version,
        "department_id": str(c.department_id) if c.department_id else None,
        "created_by": str(c.created_by) if c.created_by else None,
        "signed_at": c.signed_at.isoformat() if c.signed_at else None,
        "expires_at": c.expires_at.isoformat() if c.expires_at else None,
        "created_at": c.created_at.isoformat() if c.created_at else None,
        "updated_at": c.updated_at.isoformat() if c.updated_at else None,
    }


def _supplier_row(s: Supplier) -> dict:
    return {
        "id": str(s.id),
        "name": s.name,
        "type": s.type,
        "contact_person": s.contact_person,
        "contact_phone": s.contact_phone,
        "contact_email": s.contact_email,
        "tags": s.tags,
        "expertise": s.expertise,
        "rating": s.rating,
        "status": s.status,
        "notes": s.notes,
        "department_id": str(s.department_id) if s.department_id else None,
        "created_at": s.created_at.isoformat() if s.created_at else None,
        "updated_at": s.updated_at.isoformat() if s.updated_at else None,
    }


def _instructor_row(i: Instructor) -> dict:
    return {
        "id": str(i.id),
        "name": i.name,
        "supplier_id": str(i.supplier_id) if i.supplier_id else None,
        "expertise": i.expertise,
        "tags": i.tags,
        "qualifications": i.qualifications,
        "experience_years": i.experience_years,
        "courses_taught": i.courses_taught,
        "rating": i.rating,
        "status": i.status,
        "notes": i.notes,
        "department_id": str(i.department_id) if i.department_id else None,
    }


# ── Contract Templates ──

@router.get("/templates")
async def list_templates(
    type: str = "",
    limit: int = 50,
    offset: int = 0,
    db: AsyncSession = Depends(get_db),
    user: User = Depends(get_current_user),
):
    query = select(ContractTemplate).order_by(ContractTemplate.updated_at.desc())
    if user.role != "admin":
        if user.department_id:
            query = query.where(ContractTemplate.department_id == user.department_id)
        else:
            query = query.where(ContractTemplate.created_by == user.id)
    if type:
        query = query.where(ContractTemplate.type == type)
    result = await db.execute(query.offset(offset).limit(limit))
    return {"items": [_template_row(t) for t in result.scalars().all()]}


@router.post("/templates")
async def create_template(
    body: TemplateCreate,
    request: Request = None,
    db: AsyncSession = Depends(get_db),
    user: User = Depends(get_current_user),
):
    t = ContractTemplate(
        name=body.name,
        type=body.type,
        content=body.content,
        system_prompt=body.system_prompt,
        department_id=user.department_id,
        created_by=user.id,
    )
    db.add(t)
    await db.commit()
    await db.refresh(t)
    await audit_log(db, user, "template_create", "contract_template", t.id, t.name, "success", request=request)
    return _template_row(t)


@router.put("/templates/{template_id}")
async def update_template(
    template_id: str,
    body: TemplateUpdate,
    request: Request = None,
    db: AsyncSession = Depends(get_db),
    user: User = Depends(get_current_user),
):
    t = await _get_template(template_id, db)
    for field, val in body.model_dump(exclude_unset=True).items():
        setattr(t, field, val)
    await db.commit()
    await db.refresh(t)
    await audit_log(db, user, "template_update", "contract_template", t.id, t.name, "success", request=request)
    return _template_row(t)


@router.delete("/templates/{template_id}")
async def delete_template(
    template_id: str,
    request: Request = None,
    db: AsyncSession = Depends(get_db),
    user: User = Depends(get_current_user),
):
    t = await _get_template(template_id, db)
    await db.delete(t)
    await db.commit()
    await audit_log(db, user, "template_delete", "contract_template", t.id, t.name, "success", request=request)
    return {"message": "已删除"}


# ── Contracts ──

CONTRACT_GENERATE_PROMPT = """你是一个专业的合同撰写专家。根据用户提供的模板框架和变量，生成一份完整的合同文本。

合同应包含标准条款，语言严谨规范。变量用方括号标注的，请用提供的值替换。
如果模板中没有明确条款，请根据合同类型补充合理条款。

使用Markdown格式输出。"""


@router.get("/contracts")
async def list_contracts(
    status: str = "",
    limit: int = 50,
    offset: int = 0,
    db: AsyncSession = Depends(get_db),
    user: User = Depends(get_current_user),
):
    query = select(Contract).order_by(Contract.updated_at.desc())
    if user.role != "admin":
        if user.department_id:
            query = query.where(Contract.department_id == user.department_id)
        else:
            query = query.where(Contract.created_by == user.id)
    if status:
        query = query.where(Contract.status == status)
    result = await db.execute(query.offset(offset).limit(limit))
    return {"items": [_contract_row(c) for c in result.scalars().all()]}


@router.post("/contracts")
async def generate_contract(
    body: ContractGenerateRequest,
    request: Request = None,
    db: AsyncSession = Depends(get_db),
    user: User = Depends(get_current_user),
):
    template_content = ""
    system_prompt = CONTRACT_GENERATE_PROMPT

    if body.template_id:
        t = await _get_template(body.template_id, db)
        template_content = f"合同模板框架：\n\n{t.content}"
        if t.system_prompt:
            system_prompt = t.system_prompt

    vars_text = "\n".join(f"- {k}: {v}" for k, v in body.variables.items())
    user_prompt = f"请生成以下合同：\n\n标题：{body.title}\n对方：{body.counterparty}\n{template_content}\n变量替换：\n{vars_text}"

    llm = get_llm()
    try:
        resp = await llm.generate(
            system_prompt=system_prompt,
            user_prompt=user_prompt,
            config=LLMConfig(temperature=0.5, max_tokens=4096),
        )
    except Exception as e:
        raise HTTPException(status_code=502, detail=f"LLM调用失败: {e}")

    c = Contract(
        title=body.title,
        template_id=uuid.UUID(body.template_id) if body.template_id else None,
        counterparty=body.counterparty,
        status="draft",
        current_version=1,
        department_id=user.department_id,
        created_by=user.id,
    )
    db.add(c)
    await db.commit()
    await db.refresh(c)

    cv = ContractVersion(
        contract_id=c.id,
        version_number=1,
        content=resp.content,
        change_summary="初始版本",
        created_by=user.id,
    )
    db.add(cv)
    await db.commit()

    await audit_log(db, user, "contract_generate", "contract", c.id, c.title, "success", f"model={resp.model}", request=request)
    await es_index(str(c.id), "contracts", c.title, resp.content or "", extra=c.status or "", department_id=str(user.department_id) if user.department_id else None)
    return {
        "id": str(c.id),
        "title": c.title,
        "content": resp.content,
        "version_number": 1,
        "model": resp.model,
    }


@router.get("/contracts/{contract_id}")
async def get_contract(
    contract_id: str,
    db: AsyncSession = Depends(get_db),
    user: User = Depends(get_current_user),
):
    c = await _get_contract(contract_id, db, user)
    cv = (await db.execute(
        select(ContractVersion)
        .where(ContractVersion.contract_id == uuid.UUID(contract_id))
        .order_by(ContractVersion.version_number.desc())
        .limit(1)
    )).scalar_one_or_none()

    return {
        **_contract_row(c),
        "content": cv.content if cv else "",
        "content_html": _md_to_html(cv.content) if cv else "",
    }


@router.put("/contracts/{contract_id}")
async def update_contract(
    contract_id: str,
    body: ContractUpdate,
    request: Request = None,
    db: AsyncSession = Depends(get_db),
    user: User = Depends(get_current_user),
):
    c = await _get_contract(contract_id, db, user)
    for field, val in body.model_dump(exclude_unset=True).items():
        if field in ("signed_at", "expires_at") and val:
            val = datetime.fromisoformat(val)
        setattr(c, field, val)
    await db.commit()
    await db.refresh(c)
    await audit_log(db, user, "contract_update", "contract", c.id, c.title, "success", request=request)
    await es_index(str(c.id), "contracts", c.title, "", extra=c.status or "", department_id=str(user.department_id) if user.department_id else None)
    return _contract_row(c)


@router.delete("/contracts/{contract_id}")
async def delete_contract(
    contract_id: str,
    request: Request = None,
    db: AsyncSession = Depends(get_db),
    user: User = Depends(get_current_user),
):
    c = await _get_contract(contract_id, db, user)
    await db.delete(c)
    await db.commit()
    await audit_log(db, user, "contract_delete", "contract", c.id, c.title, "success", request=request)
    await es_delete(str(c.id), "contracts")
    return {"message": "已删除"}


@router.get("/contracts/{contract_id}/versions")
async def list_contract_versions(
    contract_id: str,
    db: AsyncSession = Depends(get_db),
    user: User = Depends(get_current_user),
):
    await _get_contract(contract_id, db, user)
    result = await db.execute(
        select(ContractVersion)
        .where(ContractVersion.contract_id == uuid.UUID(contract_id))
        .order_by(ContractVersion.version_number.desc())
    )
    return {
        "items": [
            {
                "id": str(v.id),
                "version_number": v.version_number,
                "content": v.content,
                "change_summary": v.change_summary,
                "created_by": str(v.created_by) if v.created_by else None,
                "created_at": v.created_at.isoformat() if v.created_at else None,
            }
            for v in result.scalars().all()
        ]
    }


@router.get("/contracts/{contract_id}/diff")
async def contract_diff(
    contract_id: str,
    v1: int,
    v2: int,
    db: AsyncSession = Depends(get_db),
    user: User = Depends(get_current_user),
):
    await _get_contract(contract_id, db, user)
    ver1 = (await db.execute(
        select(ContractVersion)
        .where(ContractVersion.contract_id == uuid.UUID(contract_id))
        .where(ContractVersion.version_number == v1)
    )).scalar_one_or_none()
    ver2 = (await db.execute(
        select(ContractVersion)
        .where(ContractVersion.contract_id == uuid.UUID(contract_id))
        .where(ContractVersion.version_number == v2)
    )).scalar_one_or_none()

    if not ver1 or not ver2:
        raise HTTPException(status_code=404, detail="版本不存在")

    text1 = (ver1.content or "").splitlines(keepends=True)
    text2 = (ver2.content or "").splitlines(keepends=True)
    diff_lines = list(difflib.unified_diff(
        text1, text2,
        fromfile=f"v{ver1.version_number}",
        tofile=f"v{ver2.version_number}",
    ))

    return {
        "v1": {"version_number": ver1.version_number, "created_at": ver1.created_at.isoformat() if ver1.created_at else None},
        "v2": {"version_number": ver2.version_number, "created_at": ver2.created_at.isoformat() if ver2.created_at else None},
        "diff": "".join(diff_lines),
    }


# ── Knowledge Dirs ──

@router.get("/knowledge/dirs")
async def list_knowledge_dirs(
    parent_id: str | None = None,
    db: AsyncSession = Depends(get_db),
    user: User = Depends(get_current_user),
):
    dept_id = user.department_id if user.role != "admin" else None

    # 确保"未分类"目录始终存在 — 为每个部门创建
    # 先获取用户所属部门
    user_dept = user.department_id
    if user.role == "admin" and not user_dept:
        # admin 无部门时取第一个部门
        all_depts = (await db.execute(select(Department).limit(1))).scalars().all()
        if all_depts:
            user_dept = all_depts[0].id
    if user_dept:
        dept_uuid = uuid.UUID(user_dept) if isinstance(user_dept, str) else user_dept
        result = await db.execute(
            select(BiddingKnowledgeDir).where(
                BiddingKnowledgeDir.department_id == dept_uuid,
                BiddingKnowledgeDir.name == "未分类",
                BiddingKnowledgeDir.parent_id.is_(None),
            )
        )
        if not result.scalar_one_or_none():
            db.add(BiddingKnowledgeDir(name="未分类", department_id=dept_uuid))
            await db.commit()

    query = select(BiddingKnowledgeDir).order_by(BiddingKnowledgeDir.name)
    if dept_id:
        query = query.where(BiddingKnowledgeDir.department_id == dept_id)
    if parent_id is not None:
        if parent_id == "":
            query = query.where(BiddingKnowledgeDir.parent_id.is_(None))
        else:
            query = query.where(BiddingKnowledgeDir.parent_id == uuid.UUID(parent_id))
    result = await db.execute(query)
    return {
        "items": [
            {"id": str(d.id), "name": d.name, "parent_id": str(d.parent_id) if d.parent_id else None}
            for d in result.scalars().all()
        ]
    }


@router.post("/knowledge/dirs")
async def create_knowledge_dir(
    body: KnowledgeDirCreate,
    db: AsyncSession = Depends(get_db),
    user: User = Depends(get_current_user),
):
    d = BiddingKnowledgeDir(
        name=body.name,
        parent_id=uuid.UUID(body.parent_id) if body.parent_id else None,
        department_id=user.department_id,
    )
    db.add(d)
    await db.commit()
    await db.refresh(d)
    return {"id": str(d.id), "name": d.name, "parent_id": str(d.parent_id) if d.parent_id else None}


@router.put("/knowledge/dirs/{dir_id}")
async def update_knowledge_dir(
    dir_id: str,
    body: KnowledgeDirCreate,
    db: AsyncSession = Depends(get_db),
    user: User = Depends(get_current_user),
):
    result = await db.execute(select(BiddingKnowledgeDir).where(BiddingKnowledgeDir.id == uuid.UUID(dir_id)))
    d = result.scalar_one_or_none()
    if not d:
        raise HTTPException(status_code=404, detail="目录不存在")
    d.name = body.name
    d.parent_id = uuid.UUID(body.parent_id) if body.parent_id else None
    await db.commit()
    return {"id": str(d.id), "name": d.name}


@router.delete("/knowledge/dirs/{dir_id}")
async def delete_knowledge_dir(
    dir_id: str,
    db: AsyncSession = Depends(get_db),
    user: User = Depends(get_current_user),
):
    result = await db.execute(select(BiddingKnowledgeDir).where(BiddingKnowledgeDir.id == uuid.UUID(dir_id)))
    d = result.scalar_one_or_none()
    if not d:
        raise HTTPException(status_code=404, detail="目录不存在")
    await db.delete(d)
    await db.commit()
    return {"message": "已删除"}


# ── Knowledge Docs ──

@router.get("/knowledge/docs")
async def list_knowledge_docs(
    dir_id: str = "",
    search: str = "",
    tags: str = "",
    limit: int = 50,
    offset: int = 0,
    db: AsyncSession = Depends(get_db),
    user: User = Depends(get_current_user),
):
    query = select(BiddingKnowledgeDoc).order_by(BiddingKnowledgeDoc.updated_at.desc())
    if user.role != "admin":
        if user.department_id:
            query = query.where(BiddingKnowledgeDoc.department_id == user.department_id)
        else:
            query = query.where(BiddingKnowledgeDoc.created_by == user.id)
    if dir_id:
        query = query.where(BiddingKnowledgeDoc.dir_id == uuid.UUID(dir_id))
    if search:
        from app.services.search import search as es_search
        es_result = await es_search(query=search, module="bidding_knowledge", size=200)
        ids = [item["doc_id"] for item in es_result["items"]]
        if ids:
            from uuid import UUID
            query = query.where(BiddingKnowledgeDoc.id.in_([UUID(i) for i in ids]))
        else:
            return {"items": [], "total": 0}
    result = await db.execute(query.offset(offset).limit(limit))
    rows = result.scalars().all()

    if tags:
        tag_list = [t.strip() for t in tags.split(",") if t.strip()]
        rows = [r for r in rows if r.tags and any(t in r.tags for t in tag_list)]

    return {
        "items": [
            {
                "id": str(d.id),
                "dir_id": str(d.dir_id) if d.dir_id else None,
                "title": d.title,
                "content_preview": d.content[:300] if d.content else "",
                "tags": d.tags,
                "file_id": str(d.file_id) if d.file_id else None,
                "created_at": d.created_at.isoformat() if d.created_at else None,
                "updated_at": d.updated_at.isoformat() if d.updated_at else None,
            }
            for d in rows
        ]
    }


@router.post("/knowledge/docs")
async def create_knowledge_doc(
    body: KnowledgeDocCreate,
    request: Request = None,
    db: AsyncSession = Depends(get_db),
    user: User = Depends(get_current_user),
):
    d = BiddingKnowledgeDoc(
        dir_id=uuid.UUID(body.dir_id) if body.dir_id else None,
        title=body.title,
        content=body.content,
        tags=body.tags,
        department_id=user.department_id,
        created_by=user.id,
    )
    db.add(d)
    await db.commit()
    await db.refresh(d)
    await audit_log(db, user, "knowledge_doc_create", "bidding_knowledge_doc", d.id, d.title, "success", request=request)
    return {"id": str(d.id), "title": d.title, "content": d.content, "tags": d.tags}


@router.post("/knowledge/docs/upload")
async def upload_knowledge_doc(
    file: UploadFile = FastAPIFile(...),
    dir_id: str = "",
    tags: str = "",
    request: Request = None,
    db: AsyncSession = Depends(get_db),
    user: User = Depends(get_current_user),
):
    contents = await file.read()
    storage_path = f"bidding_knowledge/{uuid.uuid4()}/{file.filename}"

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

    d = BiddingKnowledgeDoc(
        dir_id=uuid.UUID(dir_id) if dir_id else None,
        title=file.filename,
        content=extracted,
        tags=tag_list,
        file_id=file_record.id,
        department_id=user.department_id,
        created_by=user.id,
    )
    db.add(d)
    await db.commit()
    await db.refresh(d)

    await audit_log(db, user, "knowledge_doc_upload", "bidding_knowledge_doc", d.id, d.title, "success", f"file={file.filename}", request=request)
    await es_index(str(d.id), "bidding_knowledge", d.title, d.content or "",
                   extra=", ".join(d.tags) if d.tags else "",
                   department_id=str(user.department_id) if user.department_id else None)
    return {
        "id": str(d.id),
        "dir_id": str(d.dir_id) if d.dir_id else None,
        "title": d.title,
        "content": d.content,
        "content_preview": d.content[:300] if d.content else "",
        "tags": d.tags,
        "file_id": str(d.file_id) if d.file_id else None,
    }


@router.get("/knowledge/docs/{doc_id}/file-url")
async def doc_file_url(
    doc_id: str,
    db: AsyncSession = Depends(get_db),
    user: User = Depends(get_current_user),
):
    result = await db.execute(select(BiddingKnowledgeDoc).where(BiddingKnowledgeDoc.id == uuid.UUID(doc_id)))
    d = result.scalar_one_or_none()
    if not d or not d.file_id:
        raise HTTPException(status_code=404, detail="文件不存在")
    result2 = await db.execute(select(File).where(File.id == d.file_id))
    f = result2.scalar_one_or_none()
    if not f:
        raise HTTPException(status_code=404, detail="源文件不存在")
    url = await get_presigned_url(f.storage_path)
    return {"url": url, "name": f.name, "mime_type": f.mime_type, "size_bytes": f.size_bytes}


@router.delete("/knowledge/docs/{doc_id}/file")
async def doc_file_delete(
    doc_id: str,
    request: Request = None,
    db: AsyncSession = Depends(get_db),
    user: User = Depends(get_current_user),
):
    result = await db.execute(select(BiddingKnowledgeDoc).where(BiddingKnowledgeDoc.id == uuid.UUID(doc_id)))
    d = result.scalar_one_or_none()
    if not d or not d.file_id:
        raise HTTPException(status_code=404, detail="文件不存在")
    fid = d.file_id
    result2 = await db.execute(select(File).where(File.id == fid))
    f = result2.scalar_one_or_none()
    if f:
        await delete_file(f.storage_path)
        await db.delete(f)
    d.file_id = None
    d.content = ""
    await db.commit()
    await audit_log(db, user, "knowledge_doc_file_delete", "bidding_knowledge_doc", d.id, d.title, "success", request=request)
    return {"message": "文件已删除"}


# ── Knowledge QA ──

BIDDING_QA_PRECISE = """你是招投标知识库问答助手。严格基于知识库内容回答，不得编造。

规则：
- 每句话都要有知识库依据，标注来源文件名
- 找不到 → "知识库中暂无相关内容"
- 简洁专业，不推测"""

BIDDING_QA_FLEXIBLE = """你是招投标业务同事，自然专业地帮助大家。

规则：
- 优先基于知识库内容，自然融入回答
- 可补充行业经验，用【个人看法】开头
- 知识库没有的 → "这块我还不太确定"
- 简单问题聊两句，复杂问题才展开"""

BIDDING_QA_HISTORY_PROMPT = """之前对话：
{history}

结合对话历史和知识库，回答用户最新问题。"""


@router.post("/knowledge/qa")
async def bidding_knowledge_qa(
    body: dict,  # {question, mode, top_k, history}
    db: AsyncSession = Depends(get_db),
    user: User = Depends(get_current_user),
):
    question = body.get("question", "")
    mode = body.get("mode", "flexible")
    top_k = body.get("top_k", 12 if mode == "flexible" else 6)
    history = body.get("history", [])

    if not question.strip():
        raise HTTPException(status_code=400, detail="问题不能为空")

    system_prompt = BIDDING_QA_PRECISE if mode == "precise" else BIDDING_QA_FLEXIBLE
    temperature = 0.1 if mode == "precise" else 0.3
    max_tokens = 2000 if mode == "precise" else 4096

    search_text = question
    if history:
        last_assistant = ""
        for h in reversed(history):
            if h.get("role") == "assistant":
                last_assistant = h.get("content", "")
                break
        if last_assistant:
            search_text = f"{question} {last_assistant[:200]}"

    query = select(BiddingKnowledgeDoc).order_by(BiddingKnowledgeDoc.updated_at.desc())
    if user.role != "admin":
        if user.department_id:
            query = query.where(BiddingKnowledgeDoc.department_id == user.department_id)
        else:
            query = query.where(BiddingKnowledgeDoc.created_by == user.id)
    query = query.where(
        BiddingKnowledgeDoc.title.ilike(f"%{search_text}%")
        | BiddingKnowledgeDoc.content.ilike(f"%{search_text}%")
    )
    result = await db.execute(query.limit(top_k))
    docs = result.scalars().all()

    if not docs:
        # Fallback: pg_trgm word_similarity for Chinese semantic search
        query = select(BiddingKnowledgeDoc).order_by(BiddingKnowledgeDoc.updated_at.desc())
        if user.role != "admin":
            if user.department_id:
                query = query.where(BiddingKnowledgeDoc.department_id == user.department_id)
            else:
                query = query.where(BiddingKnowledgeDoc.created_by == user.id)
        query = query.where(
            (func.word_similarity(BiddingKnowledgeDoc.title, search_text) > 0.1)
            | (func.word_similarity(BiddingKnowledgeDoc.content, search_text) > 0.1)
        ).order_by(func.greatest(func.word_similarity(BiddingKnowledgeDoc.title, search_text),
                                   func.word_similarity(BiddingKnowledgeDoc.content, search_text)).desc()).limit(top_k)
        result = await db.execute(query)
        docs = result.scalars().all()

    sources = [
        {
            "id": str(d.id), "title": d.title, "content_preview": d.content[:150] if d.content else "",
            "source_file_id": str(d.file_id) if d.file_id else None,
        }
        for d in docs
    ]

    if docs:
        context_parts = [f"[{i}] 【{d.title}】\n{d.content[:1000]}" for i, d in enumerate(docs, 1)]
        context = "\n\n---\n\n".join(context_parts)
        user_prompt = f"知识库内容：\n\n{context}\n\n用户问题：{question}"
    else:
        user_prompt = f"（知识库中未找到与该问题直接相关的资料。）\n\n用户问题：{question}"

    if history:
        history_str = "\n".join(
            f"{'👤 用户' if h['role'] == 'user' else '🤖 助手'}：{h['content']}"
            for h in history[-10:]
        )
        prefix = f"知识库内容：\n\n{context}\n\n" if docs else "（知识库中未找到与该问题直接相关的资料。）\n\n"
        user_prompt = f"{prefix}{BIDDING_QA_HISTORY_PROMPT.format(history=history_str)}\n\n用户最新问题：{question}"

    llm = get_llm()
    try:
        resp = await llm.generate(
            system_prompt=system_prompt,
            user_prompt=user_prompt,
            config=LLMConfig(temperature=temperature, max_tokens=max_tokens),
        )
    except Exception as e:
        raise HTTPException(status_code=502, detail=f"LLM调用失败: {e}")

    qa = QAChatRecord(
        user_id=user.id,
        question=question,
        answer=resp.content,
        sources=sources,
        model=resp.model,
    )
    db.add(qa)
    await db.commit()

    return {"answer": resp.content, "sources": sources, "model": resp.model}


@router.get("/knowledge/qa-history")
async def bidding_qa_history(
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


@router.get("/knowledge/docs/{doc_id}")
async def get_knowledge_doc(
    doc_id: str,
    db: AsyncSession = Depends(get_db),
    user: User = Depends(get_current_user),
):
    result = await db.execute(select(BiddingKnowledgeDoc).where(BiddingKnowledgeDoc.id == uuid.UUID(doc_id)))
    d = result.scalar_one_or_none()
    if not d:
        raise HTTPException(status_code=404, detail="文档不存在")
    return {
        "id": str(d.id),
        "dir_id": str(d.dir_id) if d.dir_id else None,
        "title": d.title,
        "content": d.content,
        "tags": d.tags,
        "file_id": str(d.file_id) if d.file_id else None,
        "created_at": d.created_at.isoformat() if d.created_at else None,
        "updated_at": d.updated_at.isoformat() if d.updated_at else None,
    }


@router.put("/knowledge/docs/{doc_id}")
async def update_knowledge_doc(
    doc_id: str,
    body: KnowledgeDocUpdate,
    request: Request = None,
    db: AsyncSession = Depends(get_db),
    user: User = Depends(get_current_user),
):
    result = await db.execute(select(BiddingKnowledgeDoc).where(BiddingKnowledgeDoc.id == uuid.UUID(doc_id)))
    d = result.scalar_one_or_none()
    if not d:
        raise HTTPException(status_code=404, detail="文档不存在")
    for field, val in body.model_dump(exclude_unset=True).items():
        setattr(d, field, val)
    await db.commit()
    await db.refresh(d)
    await audit_log(db, user, "knowledge_doc_update", "bidding_knowledge_doc", d.id, d.title, "success", request=request)
    return {"message": "已更新"}


@router.delete("/knowledge/docs/{doc_id}")
async def delete_knowledge_doc(
    doc_id: str,
    request: Request = None,
    db: AsyncSession = Depends(get_db),
    user: User = Depends(get_current_user),
):
    result = await db.execute(select(BiddingKnowledgeDoc).where(BiddingKnowledgeDoc.id == uuid.UUID(doc_id)))
    d = result.scalar_one_or_none()
    if not d:
        raise HTTPException(status_code=404, detail="文档不存在")
    await db.delete(d)
    await db.commit()
    await audit_log(db, user, "knowledge_doc_delete", "bidding_knowledge_doc", d.id, d.title, "success", request=request)
    await es_delete(str(d.id), "bidding_knowledge")
    return {"message": "已删除"}


@router.get("/knowledge/search")
async def search_knowledge(
    q: str,
    limit: int = 20,
    db: AsyncSession = Depends(get_db),
    user: User = Depends(get_current_user),
):
    query = select(BiddingKnowledgeDoc).order_by(BiddingKnowledgeDoc.updated_at.desc()).limit(limit)
    if user.role != "admin":
        if user.department_id:
            query = query.where(BiddingKnowledgeDoc.department_id == user.department_id)
        else:
            query = query.where(BiddingKnowledgeDoc.created_by == user.id)
    query = query.where(
        BiddingKnowledgeDoc.title.ilike(f"%{q}%")
        | BiddingKnowledgeDoc.content.ilike(f"%{q}%")
    )
    result = await db.execute(query)
    return {
        "items": [
            {
                "id": str(d.id),
                "title": d.title,
                "content_preview": d.content[:300] if d.content else "",
                "tags": d.tags,
            }
            for d in result.scalars().all()
        ]
    }


@router.post("/knowledge/recommend")
async def recommend_similar(
    doc_id: str = None,
    limit: int = 5,
    db: AsyncSession = Depends(get_db),
    user: User = Depends(get_current_user),
):
    if not doc_id:
        return {"items": []}

    result = await db.execute(select(BiddingKnowledgeDoc).where(BiddingKnowledgeDoc.id == uuid.UUID(doc_id)))
    doc = result.scalar_one_or_none()
    if not doc:
        raise HTTPException(status_code=404, detail="文档不存在")

    # Simple tag-based recommendation
    if not doc.tags:
        return {"items": []}

    query = select(BiddingKnowledgeDoc).order_by(BiddingKnowledgeDoc.updated_at.desc()).limit(limit + 1)
    if user.role != "admin":
        if user.department_id:
            query = query.where(BiddingKnowledgeDoc.department_id == user.department_id)
        else:
            query = query.where(BiddingKnowledgeDoc.created_by == user.id)
    query = query.where(BiddingKnowledgeDoc.id != uuid.UUID(doc_id))
    result = await db.execute(query)
    candidates = result.scalars().all()

    scored = [
        (c, len(set(c.tags or []) & set(doc.tags or [])))
        for c in candidates
    ]
    scored.sort(key=lambda x: x[1], reverse=True)

    return {
        "items": [
            {
                "id": str(c.id), "title": c.title,
                "content_preview": c.content[:200] if c.content else "",
                "tags": c.tags, "match_score": score,
            }
            for c, score in scored[:limit]
        ]
    }


# ── Bidding Processes ──

@router.get("/processes")
async def list_processes(
    stage: str = "",
    limit: int = 50,
    offset: int = 0,
    db: AsyncSession = Depends(get_db),
    user: User = Depends(get_current_user),
):
    query = select(BiddingProcess).order_by(BiddingProcess.updated_at.desc())
    if user.role != "admin":
        if user.department_id:
            query = query.where(BiddingProcess.department_id == user.department_id)
        else:
            query = query.where(BiddingProcess.created_by == user.id)
    if stage:
        query = query.where(BiddingProcess.stage == stage)
    result = await db.execute(query.offset(offset).limit(limit))
    return {
        "items": [
            {
                "id": str(p.id),
                "project_name": p.project_name,
                "stage": p.stage,
                "deadline": p.deadline.isoformat() if p.deadline else None,
                "notes": p.notes,
                "created_at": p.created_at.isoformat() if p.created_at else None,
                "updated_at": p.updated_at.isoformat() if p.updated_at else None,
            }
            for p in result.scalars().all()
        ]
    }


@router.post("/processes")
async def create_process(
    body: ProcessCreate,
    request: Request = None,
    db: AsyncSession = Depends(get_db),
    user: User = Depends(get_current_user),
):
    p = BiddingProcess(
        project_name=body.project_name,
        stage=body.stage,
        deadline=datetime.fromisoformat(body.deadline) if body.deadline else None,
        notes=body.notes,
        department_id=user.department_id,
        created_by=user.id,
    )
    db.add(p)
    await db.commit()
    await db.refresh(p)
    await audit_log(db, user, "process_create", "bidding_process", p.id, p.project_name, "success", request=request)
    return {"id": str(p.id), "project_name": p.project_name, "stage": p.stage}


@router.put("/processes/{process_id}")
async def update_process(
    process_id: str,
    body: ProcessUpdate,
    request: Request = None,
    db: AsyncSession = Depends(get_db),
    user: User = Depends(get_current_user),
):
    result = await db.execute(select(BiddingProcess).where(BiddingProcess.id == uuid.UUID(process_id)))
    p = result.scalar_one_or_none()
    if not p:
        raise HTTPException(status_code=404, detail="流程不存在")
    for field, val in body.model_dump(exclude_unset=True).items():
        if field == "deadline" and val:
            val = datetime.fromisoformat(val)
        setattr(p, field, val)
    await db.commit()
    await audit_log(db, user, "process_update", "bidding_process", p.id, p.project_name, "success", request=request)
    return {"message": "已更新"}


@router.delete("/processes/{process_id}")
async def delete_process(
    process_id: str,
    request: Request = None,
    db: AsyncSession = Depends(get_db),
    user: User = Depends(get_current_user),
):
    result = await db.execute(select(BiddingProcess).where(BiddingProcess.id == uuid.UUID(process_id)))
    p = result.scalar_one_or_none()
    if not p:
        raise HTTPException(status_code=404, detail="流程不存在")
    await db.delete(p)
    await db.commit()
    await audit_log(db, user, "process_delete", "bidding_process", p.id, p.project_name, "success", request=request)
    return {"message": "已删除"}


# ── Suppliers ──

@router.get("/suppliers")
async def list_suppliers(
    type: str = "",
    search: str = "",
    limit: int = 50,
    offset: int = 0,
    db: AsyncSession = Depends(get_db),
    user: User = Depends(get_current_user),
):
    query = select(Supplier).order_by(Supplier.updated_at.desc())
    if user.role != "admin":
        if user.department_id:
            query = query.where(Supplier.department_id == user.department_id)
        else:
            query = query.where(Supplier.created_by == user.id)
    if type:
        query = query.where(Supplier.type == type)
    if search:
        from app.services.search import search as es_search
        es_result = await es_search(query=search, module="suppliers", size=200)
        ids = [item["doc_id"] for item in es_result["items"]]
        if ids:
            from uuid import UUID
            query = query.where(Supplier.id.in_([UUID(i) for i in ids]))
        else:
            return {"items": [], "total": 0}
    result = await db.execute(query.offset(offset).limit(limit))
    return {"items": [_supplier_row(s) for s in result.scalars().all()]}


@router.post("/suppliers")
async def create_supplier(
    body: SupplierCreate,
    request: Request = None,
    db: AsyncSession = Depends(get_db),
    user: User = Depends(get_current_user),
):
    s = Supplier(
        name=body.name,
        type=body.type,
        contact_person=body.contact_person,
        contact_phone=body.contact_phone,
        contact_email=body.contact_email,
        tags=body.tags,
        expertise=body.expertise,
        rating=body.rating,
        notes=body.notes,
        department_id=user.department_id,
        created_by=user.id,
    )
    db.add(s)
    await db.commit()
    await db.refresh(s)
    await audit_log(db, user, "supplier_create", "supplier", s.id, s.name, "success", request=request)
    await es_index(str(s.id), "suppliers", s.name, ", ".join(s.expertise) if s.expertise else "",
                   extra=f"{s.contact_person} {s.contact_phone} {s.contact_email}".strip(),
                   department_id=str(user.department_id) if user.department_id else None)
    return _supplier_row(s)


@router.get("/suppliers/{supplier_id}")
async def get_supplier(
    supplier_id: str,
    db: AsyncSession = Depends(get_db),
    user: User = Depends(get_current_user),
):
    result = await db.execute(select(Supplier).where(Supplier.id == uuid.UUID(supplier_id)))
    s = result.scalar_one_or_none()
    if not s:
        raise HTTPException(status_code=404, detail="供应商不存在")
    return _supplier_row(s)


@router.put("/suppliers/{supplier_id}")
async def update_supplier(
    supplier_id: str,
    body: SupplierUpdate,
    request: Request = None,
    db: AsyncSession = Depends(get_db),
    user: User = Depends(get_current_user),
):
    result = await db.execute(select(Supplier).where(Supplier.id == uuid.UUID(supplier_id)))
    s = result.scalar_one_or_none()
    if not s:
        raise HTTPException(status_code=404, detail="供应商不存在")
    for field, val in body.model_dump(exclude_unset=True).items():
        setattr(s, field, val)
    await db.commit()
    await db.refresh(s)
    await audit_log(db, user, "supplier_update", "supplier", s.id, s.name, "success", request=request)
    await es_index(str(s.id), "suppliers", s.name, ", ".join(s.expertise) if s.expertise else "",
                   extra=f"{s.contact_person} {s.contact_phone} {s.contact_email}".strip(),
                   department_id=str(user.department_id) if user.department_id else None)
    return _supplier_row(s)


@router.delete("/suppliers/{supplier_id}")
async def delete_supplier(
    supplier_id: str,
    request: Request = None,
    db: AsyncSession = Depends(get_db),
    user: User = Depends(get_current_user),
):
    result = await db.execute(select(Supplier).where(Supplier.id == uuid.UUID(supplier_id)))
    s = result.scalar_one_or_none()
    if not s:
        raise HTTPException(status_code=404, detail="供应商不存在")
    await db.delete(s)
    await db.commit()
    await audit_log(db, user, "supplier_delete", "supplier", s.id, s.name, "success", request=request)
    await es_delete(str(s.id), "suppliers")
    return {"message": "已删除"}


# ── Instructors ──

@router.get("/instructors")
async def list_instructors(
    supplier_id: str = "",
    search: str = "",
    limit: int = 50,
    offset: int = 0,
    db: AsyncSession = Depends(get_db),
    user: User = Depends(get_current_user),
):
    query = select(Instructor).order_by(Instructor.updated_at.desc())
    if user.role != "admin":
        if user.department_id:
            query = query.where(Instructor.department_id == user.department_id)
        else:
            query = query.where(Instructor.created_by == user.id)
    if supplier_id:
        query = query.where(Instructor.supplier_id == uuid.UUID(supplier_id))
    if search:
        from app.services.search import search as es_search
        es_result = await es_search(query=search, module="instructors", size=200)
        ids = [item["doc_id"] for item in es_result["items"]]
        if ids:
            from uuid import UUID
            query = query.where(Instructor.id.in_([UUID(i) for i in ids]))
        else:
            return {"items": [], "total": 0}
    result = await db.execute(query.offset(offset).limit(limit))
    return {"items": [_instructor_row(i) for i in result.scalars().all()]}


@router.post("/instructors")
async def create_instructor(
    body: InstructorCreate,
    request: Request = None,
    db: AsyncSession = Depends(get_db),
    user: User = Depends(get_current_user),
):
    i = Instructor(
        name=body.name,
        supplier_id=uuid.UUID(body.supplier_id) if body.supplier_id else None,
        expertise=body.expertise,
        tags=body.tags,
        qualifications=body.qualifications,
        experience_years=body.experience_years,
        courses_taught=body.courses_taught,
        rating=body.rating,
        notes=body.notes,
        department_id=user.department_id,
        created_by=user.id,
    )
    db.add(i)
    await db.commit()
    await db.refresh(i)
    await audit_log(db, user, "instructor_create", "instructor", i.id, i.name, "success", request=request)
    await es_index(
        str(i.id), "instructors", i.name,
        ", ".join(i.expertise) if i.expertise else "",
        extra=i.notes or "",
        department_id=str(user.department_id) if user.department_id else None,
    )
    return _instructor_row(i)


@router.get("/instructors/{instructor_id}")
async def get_instructor(
    instructor_id: str,
    db: AsyncSession = Depends(get_db),
    user: User = Depends(get_current_user),
):
    result = await db.execute(select(Instructor).where(Instructor.id == uuid.UUID(instructor_id)))
    i = result.scalar_one_or_none()
    if not i:
        raise HTTPException(status_code=404, detail="讲师不存在")
    return _instructor_row(i)


@router.put("/instructors/{instructor_id}")
async def update_instructor(
    instructor_id: str,
    body: InstructorUpdate,
    request: Request = None,
    db: AsyncSession = Depends(get_db),
    user: User = Depends(get_current_user),
):
    result = await db.execute(select(Instructor).where(Instructor.id == uuid.UUID(instructor_id)))
    i = result.scalar_one_or_none()
    if not i:
        raise HTTPException(status_code=404, detail="讲师不存在")
    for field, val in body.model_dump(exclude_unset=True).items():
        setattr(i, field, val)
    await db.commit()
    await db.refresh(i)
    await audit_log(db, user, "instructor_update", "instructor", i.id, i.name, "success", request=request)
    await es_index(
        str(i.id), "instructors", i.name,
        ", ".join(i.expertise) if i.expertise else "",
        extra=i.notes or "",
        department_id=str(i.department_id) if i.department_id else None,
    )
    return _instructor_row(i)


@router.delete("/instructors/{instructor_id}")
async def delete_instructor(
    instructor_id: str,
    request: Request = None,
    db: AsyncSession = Depends(get_db),
    user: User = Depends(get_current_user),
):
    result = await db.execute(select(Instructor).where(Instructor.id == uuid.UUID(instructor_id)))
    i = result.scalar_one_or_none()
    if not i:
        raise HTTPException(status_code=404, detail="讲师不存在")
    await es_delete(str(i.id), "instructors")
    await db.delete(i)
    await db.commit()
    await audit_log(db, user, "instructor_delete", "instructor", i.id, i.name, "success", request=request)
    return {"message": "已删除"}


# ── Course Matching (LLM) ──

MATCH_COURSE_PROMPT = """你是一个课程与讲师匹配专家。根据课程需求，从供应商讲师库中推荐最合适的讲师。

请分析每位候选讲师的匹配度，并返回JSON格式结果。"""


@router.post("/match-course")
async def match_course(
    body: MatchCourseRequest,
    request: Request = None,
    db: AsyncSession = Depends(get_db),
    user: User = Depends(get_current_user),
):
    # Gather candidates
    s_result = await db.execute(select(Instructor).where(Instructor.status == "available").limit(20))
    instructors = s_result.scalars().all()

    if not instructors:
        return {"matches": [], "message": "无可用的讲师"}

    candidates_text = "\n".join(
        f"{idx+1}. {i.name} — 专长：{', '.join(i.expertise or [])}，"
        f"资质：{', '.join(i.qualifications or [])}，"
        f"经验：{i.experience_years}年，评分：{i.rating:.1f}"
        f"（课程：{', '.join(i.courses_taught or [])}）"
        for idx, i in enumerate(instructors)
    )

    user_prompt = f"课程需求：{body.course_name}\n额外要求：{body.requirements}\n\n候选讲师：\n{candidates_text}\n\n请为每位讲师评分（1-10分）并排序，返回JSON：{{ \"matches\": [{{\"instructor_id\": \"...\", \"name\": \"...\", \"score\": 8, \"reason\": \"...\"}}] }}"

    try:
        llm = get_llm()
        resp = await llm.generate(
            system_prompt=MATCH_COURSE_PROMPT,
            user_prompt=user_prompt,
            config=LLMConfig(temperature=0.3, max_tokens=4096),
        )
    except Exception as e:
        raise HTTPException(status_code=502, detail=f"LLM调用失败: {e}")

    try:
        parsed = json.loads(resp.content)
        matches = parsed.get("matches", [])
    except json.JSONDecodeError:
        matches = []

    await audit_log(db, user, "course_match", "instructor", None, body.course_name or body.requirements, "success", f"model={resp.model}", request=request)
    return {"matches": matches, "model": resp.model}


# ── Helpers ──

async def _get_template(template_id: str, db: AsyncSession) -> ContractTemplate:
    result = await db.execute(select(ContractTemplate).where(ContractTemplate.id == uuid.UUID(template_id)))
    t = result.scalar_one_or_none()
    if not t:
        raise HTTPException(status_code=404, detail="模板不存在")
    return t


async def _get_contract(contract_id: str, db: AsyncSession, user: User) -> Contract:
    result = await db.execute(select(Contract).where(Contract.id == uuid.UUID(contract_id)))
    c = result.scalar_one_or_none()
    if not c:
        raise HTTPException(status_code=404, detail="合同不存在")
    if user.role != "admin" and user.department_id and c.department_id != user.department_id:
        raise HTTPException(status_code=403, detail="无权访问")
    return c


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
