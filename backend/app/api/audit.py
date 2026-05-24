from fastapi import APIRouter, Depends, Query
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select, func
from app.database import get_db
from app.models import User, AuditLog
from app.security import get_current_user, require_roles

router = APIRouter(prefix="/audit", tags=["audit"])


@router.get("/logs")
async def get_logs(
    page: int = Query(1, ge=1),
    page_size: int = Query(50, ge=1, le=200),
    action: str | None = None,
    username: str | None = None,
    db: AsyncSession = Depends(get_db),
    _user: User = Depends(require_roles("admin")),
):
    conditions = []
    if action:
        conditions.append(AuditLog.action == action)
    if username:
        conditions.append(AuditLog.username.ilike(f"%{username}%"))

    base_q = select(AuditLog)
    if conditions:
        from sqlalchemy import and_
        base_q = base_q.where(and_(*conditions))
    base_q = base_q.order_by(AuditLog.created_at.desc())

    count_q = select(func.count()).select_from(AuditLog)
    if conditions:
        from sqlalchemy import and_
        count_q = count_q.where(and_(*conditions))
    total = (await db.execute(count_q)).scalar() or 0

    offset = (page - 1) * page_size
    result = await db.execute(base_q.offset(offset).limit(page_size))
    rows = result.scalars().all()

    return {
        "items": [
            {
                "id": str(r.id),
                "user_id": str(r.user_id) if r.user_id else None,
                "username": r.username,
                "action": r.action,
                "resource_type": r.resource_type,
                "resource_id": str(r.resource_id) if r.resource_id else None,
                "resource_name": r.resource_name,
                "result": r.result,
                "detail": r.detail,
                "ip_address": r.ip_address,
                "user_agent": r.user_agent,
                "created_at": r.created_at.isoformat() if r.created_at else None,
            }
            for r in rows
        ],
        "total": total,
        "page": page,
        "page_size": page_size,
    }
