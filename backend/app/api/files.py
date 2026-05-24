import uuid
from fastapi import APIRouter, Depends, HTTPException, UploadFile, File as FastAPIFile, Request
from pydantic import BaseModel
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select, func
from app.database import get_db
from app.models import User, File
from app.security import get_current_user
from app.services.storage import upload_file, delete_file
from app.services.audit import log as audit_log

router = APIRouter(prefix="/files", tags=["files"])


class FolderCreate(BaseModel):
    name: str
    parent_id: str | None = None


@router.get("/list")
async def list_files(
    parent_id: str | None = None,
    page: int = 1,
    page_size: int = 50,
    search: str = "",
    db: AsyncSession = Depends(get_db),
    _user: User = Depends(get_current_user),
):
    q = select(File).where(File.parent_id == (uuid.UUID(parent_id) if parent_id else None))
    if search:
        q = q.where(File.name.ilike(f"%{search}%"))
    q = q.order_by(File.is_folder.desc(), File.created_at.desc())

    total_q = select(func.count()).select_from(File).where(
        File.parent_id == (uuid.UUID(parent_id) if parent_id else None)
    )
    total = (await db.execute(total_q)).scalar() or 0

    offset = (page - 1) * page_size
    result = await db.execute(q.offset(offset).limit(page_size))
    rows = result.scalars().all()

    return {
        "items": [
            {
                "id": str(r.id),
                "name": r.name,
                "is_folder": r.is_folder,
                "parent_id": str(r.parent_id) if r.parent_id else None,
                "mime_type": r.mime_type,
                "size_bytes": r.size_bytes,
                "created_at": r.created_at.isoformat() if r.created_at else None,
            }
            for r in rows
        ],
        "total": total,
        "page": page,
        "page_size": page_size,
    }


@router.post("/upload")
async def upload(
    file: UploadFile = FastAPIFile(...),
    parent_id: str | None = None,
    request: Request = None,
    db: AsyncSession = Depends(get_db),
    user: User = Depends(get_current_user),
):
    contents = await file.read()
    storage_path = f"files/{uuid.uuid4()}/{file.filename}"

    await upload_file(storage_path, contents, file.content_type or "application/octet-stream")

    record = File(
        name=file.filename,
        is_folder=False,
        parent_id=uuid.UUID(parent_id) if parent_id else None,
        mime_type=file.content_type or "",
        size_bytes=len(contents),
        storage_path=storage_path,
        uploaded_by=user.id,
    )
    db.add(record)
    await db.commit()
    await db.refresh(record)

    await audit_log(db, user, "upload", "file", record.id, record.name, request=request)

    return {"id": str(record.id), "name": record.name, "size_bytes": record.size_bytes}


@router.post("/folder")
async def create_folder(
    body: FolderCreate,
    request: Request = None,
    db: AsyncSession = Depends(get_db),
    user: User = Depends(get_current_user),
):
    folder = File(
        name=body.name,
        is_folder=True,
        parent_id=uuid.UUID(body.parent_id) if body.parent_id else None,
    )
    db.add(folder)
    await db.commit()
    await db.refresh(folder)

    await audit_log(db, user, "create_folder", "folder", folder.id, folder.name, request=request)
    return {"id": str(folder.id), "name": folder.name}


@router.delete("/{file_id}")
async def delete(
    file_id: str,
    request: Request = None,
    db: AsyncSession = Depends(get_db),
    user: User = Depends(get_current_user),
):
    result = await db.execute(select(File).where(File.id == uuid.UUID(file_id)))
    record = result.scalar_one_or_none()
    if not record:
        raise HTTPException(status_code=404, detail="文件不存在")

    if not record.is_folder and record.storage_path:
        try:
            await delete_file(record.storage_path)
        except FileNotFoundError:
            pass

    name = record.name
    await db.delete(record)
    await db.commit()

    await audit_log(db, user, "delete", "file", uuid.UUID(file_id), name, request=request)
    return {"message": "删除成功"}
