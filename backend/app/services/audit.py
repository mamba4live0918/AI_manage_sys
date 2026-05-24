import uuid
from fastapi import Request
from sqlalchemy.ext.asyncio import AsyncSession
from app.models import AuditLog, User


async def log(
    db: AsyncSession,
    user: User | None,
    action: str,
    resource_type: str = "",
    resource_id: uuid.UUID | None = None,
    resource_name: str = "",
    result: str = "success",
    detail: str = "",
    request: Request | None = None,
):
    entry = AuditLog(
        user_id=user.id if user else None,
        username=user.username if user else "anonymous",
        action=action,
        resource_type=resource_type,
        resource_id=resource_id,
        resource_name=resource_name,
        result=result,
        detail=detail,
        ip_address=request.client.host if request and request.client else None,
        user_agent=request.headers.get("user-agent", "") if request else "",
    )
    db.add(entry)
    await db.commit()
