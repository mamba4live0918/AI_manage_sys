from datetime import datetime, timezone

from fastapi import APIRouter, Depends
from sqlalchemy import select, func
from sqlalchemy.ext.asyncio import AsyncSession

from app.database import get_db
from app.models import User, File, AuditLog, CopyHistory
from app.security import get_current_user

router = APIRouter(prefix="/dashboard", tags=["dashboard"])

_TYPE_MAP = {
    "图片": lambda m: m.startswith("image/"),
    "视频": lambda m: m.startswith("video/"),
    "音频": lambda m: m.startswith("audio/"),
    "文档": lambda m: any(
        x in m
        for x in (
            "pdf",
            "word",
            "document",
            "excel",
            "sheet",
            "presentation",
            "powerpoint",
            "msword",
            "ms-excel",
            "ms-powerpoint",
        )
    ),
}


def _category(mime: str) -> str:
    m = (mime or "").lower()
    for label, test in _TYPE_MAP.items():
        if test(m):
            return label
    return "其他"


@router.get("/stats")
async def get_dashboard_stats(
    db: AsyncSession = Depends(get_db),
    user: User = Depends(get_current_user),
):
    is_admin = user.role == "admin"

    total_users = (
        await db.execute(
            select(func.count()).select_from(User).where(User.is_active == True)
        )
    ).scalar() or 0

    file_count_q = select(func.count()).select_from(File).where(File.is_folder == False)
    storage_q = (
        select(func.coalesce(func.sum(File.size_bytes), 0))
        .select_from(File)
        .where(File.is_folder == False)
    )
    if not is_admin:
        file_count_q = file_count_q.where(File.uploaded_by == user.id)
        storage_q = storage_q.where(File.uploaded_by == user.id)

    total_files = (await db.execute(file_count_q)).scalar() or 0
    total_storage = (await db.execute(storage_q)).scalar() or 0

    copy_q = select(func.count()).select_from(CopyHistory)
    if not is_admin:
        copy_q = copy_q.where(CopyHistory.user_id == user.id)
    total_copy = (await db.execute(copy_q)).scalar() or 0

    today_start = datetime.now(timezone.utc).replace(
        hour=0, minute=0, second=0, microsecond=0
    )
    today_q = select(func.count()).select_from(AuditLog).where(
        AuditLog.created_at >= today_start
    )
    if not is_admin:
        today_q = today_q.where(AuditLog.user_id == user.id)
    today_ops = (await db.execute(today_q)).scalar() or 0

    type_q = (
        select(File.mime_type, func.count(), func.sum(File.size_bytes))
        .select_from(File)
        .where(File.is_folder == False)
    )
    if not is_admin:
        type_q = type_q.where(File.uploaded_by == user.id)
    type_result = await db.execute(type_q.group_by(File.mime_type))
    buckets: dict[str, dict] = {}
    for mime, cnt, bsum in type_result.all():
        cat = _category(mime or "")
        if cat not in buckets:
            buckets[cat] = {"type": cat, "count": 0, "total_bytes": 0}
        buckets[cat]["count"] += cnt
        buckets[cat]["total_bytes"] += bsum or 0
    storage_by_type = sorted(
        buckets.values(), key=lambda x: x["total_bytes"], reverse=True
    )

    recent_q = select(AuditLog).order_by(AuditLog.created_at.desc()).limit(5)
    if not is_admin:
        recent_q = recent_q.where(AuditLog.user_id == user.id)
    recent_result = await db.execute(recent_q)
    recent_rows = recent_result.scalars().all()
    recent_activity = [
        {
            "id": str(r.id),
            "username": r.username,
            "action": r.action,
            "resource_name": r.resource_name,
            "created_at": r.created_at.isoformat() if r.created_at else None,
        }
        for r in recent_rows
    ]

    return {
        "total_users": total_users,
        "total_files": total_files,
        "total_storage_bytes": total_storage,
        "total_copywriting_generations": total_copy,
        "today_operations": today_ops,
        "storage_by_type": storage_by_type,
        "recent_activity": recent_activity,
    }
