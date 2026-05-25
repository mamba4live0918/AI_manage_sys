import uuid
from fastapi import APIRouter, Depends, HTTPException, Request
from fastapi.responses import StreamingResponse
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select
from app.database import get_db
from app.models import User, File
from app.security import get_current_user
from app.services.storage import get_file, get_presigned_url, upload_file, delete_file
from app.services.converter import convert_to_pdf
from app.services.permission_checker import check_permission
from app.services.audit import log as audit_log

router = APIRouter(prefix="/preview", tags=["preview"])

OFFICE_MIMES = {
    "application/msword",
    "application/vnd.openxmlformats-officedocument.wordprocessingml.document",
    "application/vnd.ms-excel",
    "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
    "application/vnd.ms-powerpoint",
    "application/vnd.openxmlformats-officedocument.presentationml.presentation",
}

OFFICE_EXTENSIONS = {".doc", ".docx", ".xls", ".xlsx", ".ppt", ".pptx"}


def _is_office_file(record: File) -> bool:
    if record.mime_type in OFFICE_MIMES:
        return True
    import os
    _, ext = os.path.splitext(record.name)
    return ext.lower() in OFFICE_EXTENSIONS


async def _get_file_record(db: AsyncSession, file_id: str) -> File:
    result = await db.execute(select(File).where(File.id == uuid.UUID(file_id)))
    record = result.scalar_one_or_none()
    if not record:
        raise HTTPException(status_code=404, detail="文件不存在")
    if record.is_folder:
        raise HTTPException(status_code=400, detail="不支持预览文件夹")
    return record


@router.get("/file/{file_id}")
async def preview_file(
    file_id: str,
    request: Request = None,
    db: AsyncSession = Depends(get_db),
    user: User = Depends(get_current_user),
):
    record = await _get_file_record(db, file_id)

    if not await check_permission(db, user, record.id, "preview"):
        await audit_log(db, user, "preview", "file", record.id, record.name, "denied", "无权限", request)
        raise HTTPException(status_code=403, detail="权限不足，无法预览此文件")

    await audit_log(db, user, "preview", "file", record.id, record.name, request=request)

    mime = record.mime_type or ""

    if mime.startswith("image/") or mime.startswith("audio/") or mime.startswith("video/") or mime == "application/pdf":
        url = await get_presigned_url(record.storage_path)
        return {"type": "media", "mime_type": mime, "url": url, "name": record.name}

    if _is_office_file(record):
        data = await get_file(record.storage_path)
        pdf_bytes = await convert_to_pdf(data, record.name)
        temp_path = f"temp/preview/{file_id}.pdf"
        await upload_file(temp_path, pdf_bytes, "application/pdf")
        url = await get_presigned_url(temp_path)
        return {
            "type": "media",
            "mime_type": "application/pdf",
            "url": url,
            "name": record.name + ".pdf",
            "temp_path": temp_path,
        }

    url = await get_presigned_url(record.storage_path)
    return {"type": "raw", "mime_type": mime, "url": url, "name": record.name}


@router.post("/close/{file_id}")
async def close_preview(
    file_id: str,
    request: Request = None,
    db: AsyncSession = Depends(get_db),
    user: User = Depends(get_current_user),
):
    temp_path = f"temp/preview/{file_id}.pdf"
    try:
        await delete_file(temp_path)
    except FileNotFoundError:
        pass
    await audit_log(db, user, "preview_close", "file", uuid.UUID(file_id), temp_path, request=request)
    return {"status": "ok"}


@router.get("/download/{file_id}")
async def download_file(
    file_id: str,
    request: Request = None,
    db: AsyncSession = Depends(get_db),
    user: User = Depends(get_current_user),
):
    record = await _get_file_record(db, file_id)

    if not await check_permission(db, user, record.id, "download"):
        await audit_log(db, user, "download", "file", record.id, record.name, "denied", "无下载权限", request)
        raise HTTPException(status_code=403, detail="权限不足，无法下载此文件")

    data = await get_file(record.storage_path)
    await audit_log(db, user, "download", "file", record.id, record.name, request=request)

    return StreamingResponse(
        iter([data]),
        media_type=record.mime_type or "application/octet-stream",
        headers={"Content-Disposition": f'attachment; filename="{record.name}"'},
    )
