import uuid
from datetime import timedelta
from fastapi import APIRouter, Depends, HTTPException, Request
from fastapi.responses import StreamingResponse
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select
from app.database import get_db
from app.models import User, File
from app.security import get_current_user
from app.config import settings
from minio import Minio
from app.services.storage import get_file, get_presigned_url
from app.services.permission_checker import check_permission
from app.services.audit import log as audit_log

router = APIRouter(prefix="/preview", tags=["preview"])


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

    if mime in (
        "application/msword",
        "application/vnd.openxmlformats-officedocument.wordprocessingml.document",
        "application/vnd.ms-excel",
        "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
        "application/vnd.ms-powerpoint",
        "application/vnd.openxmlformats-officedocument.presentationml.presentation",
    ):
        base = str(request.base_url).rstrip("/") if request else f"http://localhost:8001"
        return {
            "type": "onlyoffice",
            "mime_type": mime,
            "name": record.name,
            "config_url": f"{base}{settings.API_PREFIX}/preview/onlyoffice/config/{file_id}",
        }

    url = await get_presigned_url(record.storage_path)
    return {"type": "raw", "mime_type": mime, "url": url, "name": record.name}


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


@router.get("/onlyoffice/config/{file_id}")
async def onlyoffice_config(
    file_id: str,
    db: AsyncSession = Depends(get_db),
    user: User = Depends(get_current_user),
):
    record = await _get_file_record(db, file_id)
    if not await check_permission(db, user, record.id, "preview"):
        raise HTTPException(status_code=403, detail="权限不足")

    # Generate presigned URL with host.docker.internal so OnlyOffice container
    # can reach MinIO (localhost resolves to container itself inside Docker).
    # host.docker.internal resolves to host on both Windows host and Docker containers.
    docker_minio = Minio(
        "host.docker.internal:9000",
        access_key=settings.MINIO_ACCESS_KEY,
        secret_key=settings.MINIO_SECRET_KEY,
        secure=settings.MINIO_SECURE,
    )
    file_url = docker_minio.presigned_get_object(
        settings.MINIO_BUCKET, record.storage_path, expires=timedelta(seconds=86400),
    )
    return {
        "document": {
            "fileType": record.mime_type,
            "key": str(record.id),
            "title": record.name,
            "url": file_url,
        },
        "editorConfig": {
            "mode": "view",
            "lang": "zh-CN",
            "user": {"id": str(user.id), "name": user.username},
        },
    }
