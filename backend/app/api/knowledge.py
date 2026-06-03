import uuid
from datetime import datetime, timezone

from fastapi import APIRouter, Depends, HTTPException, Request, UploadFile, File as FastAPIFile
from pydantic import BaseModel
from sqlalchemy import select, func, delete
from sqlalchemy.ext.asyncio import AsyncSession

from app.database import get_db
from app.models import User, Department, File, QAChatRecord, KBCategory, KBDocument, KBDocumentCategory
from app.security import get_current_user, require_department_access
from app.services.llm.router import get_llm
from app.services.llm.base import LLMConfig
from app.services.audit import log as audit_log
from app.services.file_extractor import extract_text
from app.services.storage import upload_file, get_presigned_url, delete_file
from app.services.search import index_document as es_index, delete_document as es_delete

router = APIRouter(prefix="/knowledge", tags=["knowledge"])


def _now():
    return datetime.now(timezone.utc)


# ── Pydantic Schemas ──

class CategoryCreate(BaseModel):
    name: str
    parent_id: str | None = None
    description: str = ""
    icon: str = "folder"
    sort_order: int = 0


class CategoryUpdate(BaseModel):
    name: str | None = None
    description: str | None = None
    icon: str | None = None
    sort_order: int | None = None
    parent_id: str | None = None


class DocumentCreate(BaseModel):
    title: str
    content: str = ""
    category_ids: list[str] = []
    tags: list[str] = []


class DocumentUpdate(BaseModel):
    title: str | None = None
    content: str | None = None
    tags: list[str] | None = None


class CategoryIdsUpdate(BaseModel):
    category_ids: list[str] = []


class DocumentMoveRequest(BaseModel):
    target_category_id: str  # 目标分类ID


class CategoryMoveRequest(BaseModel):
    target_parent_id: str | None = None  # 新父分类ID，null=移到根


@router.put("/{dept_id}/categories/{cat_id}/move")
async def move_category(
    dept_id: str,
    cat_id: str,
    body: CategoryMoveRequest,
    request: Request = None,
    db: AsyncSession = Depends(get_db),
    user: User = Depends(get_current_user),
):
    """移动子分类到另一个父分类下"""
    await require_department_access(dept_id, user)
    result = await db.execute(
        select(KBCategory).where(
            KBCategory.id == uuid.UUID(cat_id),
            KBCategory.department_id == uuid.UUID(dept_id),
        )
    )
    cat = result.scalar_one_or_none()
    if not cat:
        raise HTTPException(status_code=404, detail="分类不存在")
    # 不能把自己设为自己的父
    if body.target_parent_id and uuid.UUID(body.target_parent_id) == cat.id:
        raise HTTPException(status_code=400, detail="不能移到自身下")
    cat.parent_id = uuid.UUID(body.target_parent_id) if body.target_parent_id else None
    await db.commit()
    await audit_log(db, user, "kb_cat_move", "kb_category", cat.id,
                    f"{cat.name} → parent={body.target_parent_id}", request=request)
    return _category_row(cat)


@router.put("/{dept_id}/documents/{doc_id}/move")
async def move_document(
    dept_id: str,
    doc_id: str,
    body: DocumentMoveRequest,
    request: Request = None,
    db: AsyncSession = Depends(get_db),
    user: User = Depends(get_current_user),
):
    """移动文档到指定分类（替换分类关联）"""
    await require_department_access(dept_id, user)
    result = await db.execute(
        select(KBDocument).where(
            KBDocument.id == uuid.UUID(doc_id),
            KBDocument.department_id == uuid.UUID(dept_id),
        )
    )
    d = result.scalar_one_or_none()
    if not d:
        raise HTTPException(status_code=404, detail="文档不存在")
    # 验证目标分类存在且属于同一部门
    cat_result = await db.execute(
        select(KBCategory).where(
            KBCategory.id == uuid.UUID(body.target_category_id),
            KBCategory.department_id == uuid.UUID(dept_id),
        )
    )
    cat = cat_result.scalar_one_or_none()
    if not cat:
        raise HTTPException(status_code=404, detail="目标分类不存在")

    # 删除旧关联，添加到新分类
    await db.execute(
        delete(KBDocumentCategory).where(KBDocumentCategory.document_id == d.id)
    )
    db.add(KBDocumentCategory(document_id=d.id, category_id=cat.id))
    await db.commit()
    await audit_log(db, user, "kb_doc_move", "kb_document", d.id,
                    f"{d.title} → {cat.name}", request=request)
    return {"message": "已移动", "category_id": str(cat.id), "category_name": cat.name}


class ChatRequest(BaseModel):
    question: str
    mode: str = "flexible"  # "precise" | "flexible"
    top_k: int = 12
    history: list[dict] = []


# ── Helpers ──

def _category_row(c: KBCategory) -> dict:
    return {
        "id": str(c.id),
        "name": c.name,
        "description": c.description,
        "icon": c.icon,
        "sort_order": c.sort_order,
        "parent_id": str(c.parent_id) if c.parent_id else None,
        "department_id": str(c.department_id),
        "created_at": c.created_at.isoformat() if c.created_at else None,
    }


def _document_row(d: KBDocument) -> dict:
    return {
        "id": str(d.id),
        "title": d.title,
        "content_preview": d.content[:200] if d.content else "",
        "file_type": d.file_type,
        "tags": d.tags,
        "is_archived": d.is_archived,
        "chunk_count": d.chunk_count,
        "department_id": str(d.department_id),
        "created_by": str(d.created_by) if d.created_by else None,
        "created_at": d.created_at.isoformat() if d.created_at else None,
        "updated_at": d.updated_at.isoformat() if d.updated_at else None,
    }


# ── Department list ──

@router.get("/departments")
async def list_departments(
    db: AsyncSession = Depends(get_db),
    user: User = Depends(get_current_user),
):
    """Return departments the user can access for knowledge base"""
    if user.role == "admin":
        result = await db.execute(select(Department).order_by(Department.name))
        depts = result.scalars().all()
    else:
        dept_id = user.department_id
        if dept_id:
            result = await db.execute(select(Department).where(Department.id == dept_id))
            depts = result.scalars().all()
        else:
            depts = []
    return {
        "items": [
            {"id": str(d.id), "name": d.name, "description": d.description}
            for d in depts
        ]
    }


# ── Categories ──

@router.get("/{dept_id}/categories")
async def list_categories(
    dept_id: str,
    db: AsyncSession = Depends(get_db),
    user: User = Depends(get_current_user),
):
    await require_department_access(dept_id, user)
    department_uuid = uuid.UUID(dept_id)

    # 确保"未分类"根分类始终存在
    result = await db.execute(
        select(KBCategory).where(
            KBCategory.department_id == department_uuid,
            KBCategory.name == "未分类",
            KBCategory.parent_id.is_(None),
        )
    )
    uncategorized = result.scalar_one_or_none()
    if not uncategorized:
        uncategorized = KBCategory(
            name="未分类",
            description="未选择目录的文件",
            department_id=department_uuid,
            sort_order=-1,
        )
        db.add(uncategorized)
        await db.commit()
        await db.refresh(uncategorized)

    result = await db.execute(
        select(KBCategory)
        .where(KBCategory.department_id == department_uuid)
        .order_by(KBCategory.sort_order, KBCategory.name)
    )
    categories = result.scalars().all()

    # Count documents per category
    cat_counts = {}
    if categories:
        from sqlalchemy import text as sa_text
        for c in categories:
            count_result = await db.execute(
                sa_text("SELECT COUNT(*) FROM kb_document_categories WHERE category_id = :cid"),
                {"cid": c.id}
            )
            cat_counts[str(c.id)] = count_result.scalar()

    return {
        "items": [
            {**_category_row(c), "children": [], "document_count": cat_counts.get(str(c.id), 0)}
            for c in categories
        ]
    }


@router.post("/{dept_id}/categories")
async def create_category(
    dept_id: str,
    body: CategoryCreate,
    db: AsyncSession = Depends(get_db),
    user: User = Depends(get_current_user),
):
    await require_department_access(dept_id, user)
    c = KBCategory(
        name=body.name,
        description=body.description,
        icon=body.icon,
        sort_order=body.sort_order,
        parent_id=uuid.UUID(body.parent_id) if body.parent_id else None,
        department_id=uuid.UUID(dept_id),
    )
    db.add(c)
    await db.commit()
    await db.refresh(c)
    return _category_row(c)


@router.put("/{dept_id}/categories/{cat_id}")
async def update_category(
    dept_id: str,
    cat_id: str,
    body: CategoryUpdate,
    db: AsyncSession = Depends(get_db),
    user: User = Depends(get_current_user),
):
    await require_department_access(dept_id, user)
    result = await db.execute(
        select(KBCategory).where(
            KBCategory.id == uuid.UUID(cat_id),
            KBCategory.department_id == uuid.UUID(dept_id),
        )
    )
    c = result.scalar_one_or_none()
    if not c:
        raise HTTPException(status_code=404, detail="分类不存在")
    if body.name is not None:
        c.name = body.name
    if body.description is not None:
        c.description = body.description
    if body.icon is not None:
        c.icon = body.icon
    if body.sort_order is not None:
        c.sort_order = body.sort_order
    if body.parent_id is not None:
        c.parent_id = uuid.UUID(body.parent_id) if body.parent_id else None
    await db.commit()
    await db.refresh(c)
    return _category_row(c)


@router.delete("/{dept_id}/categories/{cat_id}")
async def delete_category(
    dept_id: str,
    cat_id: str,
    db: AsyncSession = Depends(get_db),
    user: User = Depends(get_current_user),
):
    await require_department_access(dept_id, user)
    result = await db.execute(
        select(KBCategory).where(
            KBCategory.id == uuid.UUID(cat_id),
            KBCategory.department_id == uuid.UUID(dept_id),
        )
    )
    c = result.scalar_one_or_none()
    if not c:
        raise HTTPException(status_code=404, detail="分类不存在")
    # Children are auto-promoted by ON DELETE CASCADE on parent_id,
    # but SQLAlchemy FK is ondelete="CASCADE" which deletes children.
    # We want to promote children — handle manually.
    # Promote children to this category's parent
    promote_parent = c.parent_id
    child_result = await db.execute(
        select(KBCategory).where(KBCategory.parent_id == c.id)
    )
    for child in child_result.scalars().all():
        child.parent_id = promote_parent
    # Remove document-category links
    await db.execute(
        delete(KBDocumentCategory).where(KBDocumentCategory.category_id == c.id)
    )
    await db.delete(c)
    await db.commit()
    return {"message": "已删除"}


# ── Documents ──

@router.get("/{dept_id}/documents")
async def list_documents(
    dept_id: str,
    category_id: str = "",
    search: str = "",
    tags: str = "",
    limit: int = 30,
    offset: int = 0,
    include_archived: bool = False,
    db: AsyncSession = Depends(get_db),
    user: User = Depends(get_current_user),
):
    await require_department_access(dept_id, user)
    department_uuid = uuid.UUID(dept_id)

    query = select(KBDocument).where(KBDocument.department_id == department_uuid)
    if not include_archived:
        query = query.where(KBDocument.is_archived == False)

    if category_id:
        query = query.join(
            KBDocumentCategory, KBDocumentCategory.document_id == KBDocument.id
        ).where(KBDocumentCategory.category_id == uuid.UUID(category_id))

    if search:
        from app.services.search import search as es_search
        try:
            es_result = await es_search(query=search, module="kb_documents", size=200)
            ids = [item["doc_id"] for item in es_result["items"]]
            if ids:
                query = query.where(KBDocument.id.in_([uuid.UUID(i) for i in ids]))
            else:
                return {"items": [], "total": 0}
        except Exception:
            # Fallback to ILIKE
            query = query.where(
                KBDocument.title.ilike(f"%{search}%")
                | KBDocument.content.ilike(f"%{search}%")
            )

    if tags:
        tag_list = [t.strip() for t in tags.split(",") if t.strip()]
        # Filter in Python — JSON array matching is hard in SQL
        pass  # Will filter after query

    query = query.order_by(KBDocument.updated_at.desc())
    result = await db.execute(query)
    rows = result.scalars().all()

    if tags:
        tag_list = [t.strip() for t in tags.split(",") if t.strip()]
        rows = [r for r in rows if r.tags and any(t in r.tags for t in tag_list)]

    total = len(rows)
    rows = rows[offset:offset + limit]

    # Get categories for each doc
    doc_ids = [r.id for r in rows]
    cat_map = {}
    if doc_ids:
        from sqlalchemy import text as sa_text
        link_result = await db.execute(
            sa_text(
                "SELECT dc.document_id, dc.category_id, c.name FROM kb_document_categories dc "
                "JOIN kb_categories c ON c.id = dc.category_id "
                "WHERE dc.document_id = ANY(:ids)"
            ),
            {"ids": doc_ids}
        )
        for row in link_result:
            did = str(row[0])
            if did not in cat_map:
                cat_map[did] = []
            cat_map[did].append({"id": str(row[1]), "name": row[2]})

    return {
        "items": [
            {**_document_row(d), "categories": cat_map.get(str(d.id), [])}
            for d in rows
        ],
        "total": total,
    }


@router.post("/{dept_id}/documents")
async def create_document(
    dept_id: str,
    body: DocumentCreate,
    request: Request = None,
    db: AsyncSession = Depends(get_db),
    user: User = Depends(get_current_user),
):
    await require_department_access(dept_id, user)
    department_uuid = uuid.UUID(dept_id)

    d = KBDocument(
        title=body.title,
        content=body.content,
        content_preview=body.content[:200] if body.content else "",
        tags=body.tags,
        department_id=department_uuid,
        created_by=user.id,
    )
    db.add(d)
    await db.commit()
    await db.refresh(d)

    # Link categories
    for cid in body.category_ids:
        db.add(KBDocumentCategory(document_id=d.id, category_id=uuid.UUID(cid)))

    await db.commit()
    await audit_log(db, user, "kb_doc_create", "kb_document", d.id, d.title, "success", request=request)

    # Index to ES
    try:
        await es_index(str(d.id), "kb_documents", d.title, d.content or "",
                       extra=", ".join(d.tags) if d.tags else "",
                       department_id=str(department_uuid))
    except Exception:
        pass

    return {**_document_row(d), "content": d.content}


@router.post("/{dept_id}/documents/upload")
async def upload_document(
    dept_id: str,
    file: UploadFile = FastAPIFile(...),
    category_ids: str = "",
    tags: str = "",
    request: Request = None,
    db: AsyncSession = Depends(get_db),
    user: User = Depends(get_current_user),
):
    await require_department_access(dept_id, user)
    department_uuid = uuid.UUID(dept_id)

    contents = await file.read()
    storage_path = f"kb/{uuid.uuid4()}/{file.filename}"
    file_type = file.filename.split(".")[-1].lower() if "." in file.filename else ""

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
    cat_ids = [c.strip() for c in category_ids.split(",") if c.strip()] if category_ids else []

    d = KBDocument(
        title=file.filename,
        content=extracted,
        content_preview=extracted[:200] if extracted else "",
        file_path=storage_path,
        file_type=file_type,
        tags=tag_list,
        department_id=department_uuid,
        created_by=user.id,
    )
    db.add(d)
    await db.commit()
    await db.refresh(d)

    for cid in cat_ids:
        db.add(KBDocumentCategory(document_id=d.id, category_id=uuid.UUID(cid)))
    await db.commit()

    await audit_log(db, user, "kb_doc_upload", "kb_document", d.id, d.title, "success", f"file={file.filename}", request=request)
    try:
        await es_index(str(d.id), "kb_documents", d.title, d.content or "",
                       extra=", ".join(d.tags) if d.tags else "",
                       department_id=str(department_uuid))
    except Exception:
        pass

    return {**_document_row(d), "content": extracted, "file_id": str(file_record.id)}


@router.get("/{dept_id}/documents/{doc_id}")
async def get_document(
    dept_id: str,
    doc_id: str,
    db: AsyncSession = Depends(get_db),
    user: User = Depends(get_current_user),
):
    await require_department_access(dept_id, user)
    result = await db.execute(
        select(KBDocument).where(
            KBDocument.id == uuid.UUID(doc_id),
            KBDocument.department_id == uuid.UUID(dept_id),
        )
    )
    d = result.scalar_one_or_none()
    if not d:
        raise HTTPException(status_code=404, detail="文档不存在")

    # Get categories
    from sqlalchemy import text as sa_text
    link_result = await db.execute(
        sa_text(
            "SELECT c.id, c.name FROM kb_document_categories dc "
            "JOIN kb_categories c ON c.id = dc.category_id "
            "WHERE dc.document_id = :did"
        ),
        {"did": d.id}
    )
    categories = [{"id": str(r[0]), "name": r[1]} for r in link_result]

    return {
        "id": str(d.id),
        "title": d.title,
        "content": d.content,
        "file_type": d.file_type,
        "file_path": d.file_path,
        "tags": d.tags,
        "is_archived": d.is_archived,
        "categories": categories,
        "department_id": str(d.department_id),
        "created_by": str(d.created_by) if d.created_by else None,
        "created_at": d.created_at.isoformat() if d.created_at else None,
        "updated_at": d.updated_at.isoformat() if d.updated_at else None,
    }


@router.get("/{dept_id}/documents/{doc_id}/file-url")
async def document_file_url(
    dept_id: str,
    doc_id: str,
    db: AsyncSession = Depends(get_db),
    user: User = Depends(get_current_user),
):
    await require_department_access(dept_id, user)
    result = await db.execute(
        select(KBDocument).where(
            KBDocument.id == uuid.UUID(doc_id),
            KBDocument.department_id == uuid.UUID(dept_id),
        )
    )
    d = result.scalar_one_or_none()
    if not d or not d.file_path:
        raise HTTPException(status_code=404, detail="文件不存在")
    url = await get_presigned_url(d.file_path)
    return {"url": url, "name": d.title, "file_type": d.file_type}


@router.delete("/{dept_id}/documents/{doc_id}")
async def delete_document(
    dept_id: str,
    doc_id: str,
    request: Request = None,
    db: AsyncSession = Depends(get_db),
    user: User = Depends(get_current_user),
):
    await require_department_access(dept_id, user)
    result = await db.execute(
        select(KBDocument).where(
            KBDocument.id == uuid.UUID(doc_id),
            KBDocument.department_id == uuid.UUID(dept_id),
        )
    )
    d = result.scalar_one_or_none()
    if not d:
        raise HTTPException(status_code=404, detail="文档不存在")

    # Clean file
    if d.file_path:
        try:
            await delete_file(d.file_path)
        except Exception:
            pass

    await audit_log(db, user, "kb_doc_delete", "kb_document", d.id, d.title, "success", request=request)
    try:
        await es_delete(str(d.id), "kb_documents")
    except Exception:
        pass

    await db.delete(d)
    await db.commit()
    return {"message": "已删除"}


@router.patch("/{dept_id}/documents/{doc_id}/archive")
async def archive_document(
    dept_id: str,
    doc_id: str,
    archive: bool = True,
    db: AsyncSession = Depends(get_db),
    user: User = Depends(get_current_user),
):
    await require_department_access(dept_id, user)
    result = await db.execute(
        select(KBDocument).where(
            KBDocument.id == uuid.UUID(doc_id),
            KBDocument.department_id == uuid.UUID(dept_id),
        )
    )
    d = result.scalar_one_or_none()
    if not d:
        raise HTTPException(status_code=404, detail="文档不存在")
    d.is_archived = archive
    await db.commit()
    return {"message": "已归档" if archive else "已取消归档", "is_archived": archive}


@router.put("/{dept_id}/documents/{doc_id}")
async def update_document(
    dept_id: str,
    doc_id: str,
    body: DocumentUpdate,
    request: Request = None,
    db: AsyncSession = Depends(get_db),
    user: User = Depends(get_current_user),
):
    await require_department_access(dept_id, user)
    result = await db.execute(
        select(KBDocument).where(
            KBDocument.id == uuid.UUID(doc_id),
            KBDocument.department_id == uuid.UUID(dept_id),
        )
    )
    d = result.scalar_one_or_none()
    if not d:
        raise HTTPException(status_code=404, detail="文档不存在")
    if body.title is not None:
        d.title = body.title
    if body.content is not None:
        d.content = body.content
        d.content_preview = body.content[:200]
    if body.tags is not None:
        d.tags = body.tags
    await db.commit()
    await audit_log(db, user, "kb_doc_update", "kb_document", d.id, d.title, "success", request=request)
    try:
        await es_index(str(d.id), "kb_documents", d.title, d.content or "",
                       extra=", ".join(d.tags) if d.tags else "",
                       department_id=str(d.department_id))
    except Exception:
        pass
    return {**_document_row(d), "content": d.content}


@router.put("/{dept_id}/documents/{doc_id}/categories")
async def update_document_categories(
    dept_id: str,
    doc_id: str,
    body: CategoryIdsUpdate,
    db: AsyncSession = Depends(get_db),
    user: User = Depends(get_current_user),
):
    await require_department_access(dept_id, user)
    result = await db.execute(
        select(KBDocument).where(
            KBDocument.id == uuid.UUID(doc_id),
            KBDocument.department_id == uuid.UUID(dept_id),
        )
    )
    d = result.scalar_one_or_none()
    if not d:
        raise HTTPException(status_code=404, detail="文档不存在")

    # Replace all category links
    await db.execute(
        delete(KBDocumentCategory).where(KBDocumentCategory.document_id == d.id)
    )
    for cid in body.category_ids:
        db.add(KBDocumentCategory(document_id=d.id, category_id=uuid.UUID(cid)))
    await db.commit()
    return {"message": "已更新", "category_ids": body.category_ids}


# ── Chat / QA ──

KB_PRECISE_PROMPT = """你是企业知识库问答助手。你必须严格基于提供的知识库内容回答，不得编造。

规则：
- 每句话都要有知识库依据，标注来源文件名
- 找不到相关内容 → 直接说"知识库中暂无相关内容"，不要编造
- 回答简洁专业，不展开推测"""

KB_FLEXIBLE_PROMPT = """你是资深企业顾问助手兼同事。自然、专业、亲切地回答。

规则：
- 优先基于知识库内容，自然融入回答，不机械引用
- 可以补充行业经验和实操见解，用【个人看法】开头区分
- 可以跨文档综合推理
- 知识库确实没有的资料 → 坦诚说"这块我还不太确定"
- 简单问题聊两句就行，复杂问题才展开"""

KB_QA_HISTORY_PROMPT = """之前和用户的对话：
{history}

根据上面的对话历史，结合知识库内容，自然地回答用户的最新问题。注意上下文连贯，就像在继续刚才的聊天。"""


@router.post("/{dept_id}/chat")
async def knowledge_chat(
    dept_id: str,
    body: ChatRequest,
    request: Request = None,
    db: AsyncSession = Depends(get_db),
    user: User = Depends(get_current_user),
):
    await require_department_access(dept_id, user)
    department_uuid = uuid.UUID(dept_id)

    question = body.question.strip()
    if not question:
        raise HTTPException(status_code=400, detail="问题不能为空")

    mode = body.mode  # "precise" or "flexible"
    k = 6 if mode == "precise" else 12
    temperature = 0.1 if mode == "precise" else 0.3
    max_tokens = 2000 if mode == "precise" else 4096
    system_prompt = KB_PRECISE_PROMPT if mode == "precise" else KB_FLEXIBLE_PROMPT

    # Search with history context
    search_text = question
    history = body.history or []
    if history:
        for h in reversed(history):
            if h.get("role") == "assistant":
                search_text = f"{question} {h.get('content', '')[:200]}"
                break

    # ILIKE search
    query = select(KBDocument).where(
        KBDocument.department_id == department_uuid,
        KBDocument.is_archived == False,
    )
    query = query.where(
        KBDocument.title.ilike(f"%{search_text}%")
        | KBDocument.content.ilike(f"%{search_text}%")
    ).order_by(KBDocument.updated_at.desc()).limit(k)

    result = await db.execute(query)
    docs = result.scalars().all()

    # Fallback: pg_trgm word_similarity
    if not docs:
        query = select(KBDocument).where(
            KBDocument.department_id == department_uuid,
            KBDocument.is_archived == False,
        ).where(
            (func.word_similarity(KBDocument.title, search_text) > 0.1)
            | (func.word_similarity(KBDocument.content, search_text) > 0.1)
        ).order_by(
            func.greatest(
                func.word_similarity(KBDocument.title, search_text),
                func.word_similarity(KBDocument.content, search_text),
            ).desc()
        ).limit(k)
        result = await db.execute(query)
        docs = result.scalars().all()

    sources = [
        {
            "id": str(d.id), "title": d.title,
            "content_preview": d.content[:150] if d.content else "",
        }
        for d in docs
    ]

    if docs:
        context_parts = [f"[{i}] 【{d.title}】\n{d.content[:1000]}" for i, d in enumerate(docs, 1)]
        context = "\n\n---\n\n".join(context_parts)
        prefix = f"知识库内容：\n\n{context}\n\n"
    else:
        prefix = "（知识库中未找到与该问题直接相关的资料。）\n\n"

    if history:
        history_str = "\n".join(
            f"{'👤 用户' if h['role'] == 'user' else '🤖 助手'}：{h['content']}"
            for h in history[-10:]
        )
        user_prompt = f"{prefix}{KB_QA_HISTORY_PROMPT.format(history=history_str)}\n\n用户最新问题：{question}"
    else:
        user_prompt = f"{prefix}用户问题：{question}"

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

    await audit_log(db, user, "kb_chat", "qa_chat_record", qa.id, question[:100], "success", f"model={resp.model} mode={mode}", request=request)
    return {"answer": resp.content, "sources": sources, "model": resp.model, "mode": mode}


@router.get("/{dept_id}/chat/history")
async def chat_history(
    dept_id: str,
    limit: int = 50,
    offset: int = 0,
    db: AsyncSession = Depends(get_db),
    user: User = Depends(get_current_user),
):
    await require_department_access(dept_id, user)
    query = select(QAChatRecord).where(
        QAChatRecord.user_id == user.id
    ).order_by(QAChatRecord.created_at.desc()).offset(offset).limit(limit)
    result = await db.execute(query)
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
