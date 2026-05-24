import uuid
from fastapi import APIRouter, Depends, HTTPException, Request
from pydantic import BaseModel
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select
from app.database import get_db
from app.models import User, Permission
from app.security import get_current_user, require_roles
from app.services.audit import log as audit_log

router = APIRouter(prefix="/permissions", tags=["permissions"])


class GrantRequest(BaseModel):
    resource_type: str = "file"
    resource_id: str
    grantee_type: str  # user | role | department | project
    grantee_value: str
    action: str  # preview | download | edit | admin


@router.get("/resource/{resource_id}")
async def get_permissions(
    resource_id: str,
    db: AsyncSession = Depends(get_db),
    _user: User = Depends(get_current_user),
):
    result = await db.execute(
        select(Permission).where(Permission.resource_id == uuid.UUID(resource_id))
    )
    rows = result.scalars().all()
    return {
        "items": [
            {
                "id": str(r.id),
                "resource_type": r.resource_type,
                "resource_id": str(r.resource_id),
                "grantee_type": r.grantee_type,
                "grantee_value": r.grantee_value,
                "action": r.action,
            }
            for r in rows
        ]
    }


@router.post("/grant")
async def grant(
    body: GrantRequest,
    request: Request = None,
    db: AsyncSession = Depends(get_db),
    user: User = Depends(require_roles("admin")),
):
    existing = await db.execute(
        select(Permission).where(
            Permission.resource_type == body.resource_type,
            Permission.resource_id == uuid.UUID(body.resource_id),
            Permission.grantee_type == body.grantee_type,
            Permission.grantee_value == body.grantee_value,
            Permission.action == body.action,
        )
    )
    if existing.scalar_one_or_none():
        raise HTTPException(status_code=409, detail="该权限已存在")

    perm = Permission(
        resource_type=body.resource_type,
        resource_id=uuid.UUID(body.resource_id),
        grantee_type=body.grantee_type,
        grantee_value=body.grantee_value,
        action=body.action,
        granted_by=user.id,
    )
    db.add(perm)
    await db.commit()
    await db.refresh(perm)

    await audit_log(
        db, user, "permission_change", "permission", perm.id,
        f"grant {body.grantee_type}:{body.grantee_value} {body.action}",
        request=request,
    )
    return {"id": str(perm.id)}


@router.delete("/revoke/{perm_id}")
async def revoke(
    perm_id: str,
    request: Request = None,
    db: AsyncSession = Depends(get_db),
    user: User = Depends(require_roles("admin")),
):
    result = await db.execute(select(Permission).where(Permission.id == uuid.UUID(perm_id)))
    perm = result.scalar_one_or_none()
    if not perm:
        raise HTTPException(status_code=404, detail="权限不存在")

    detail = f"revoke {perm.grantee_type}:{perm.grantee_value} {perm.action}"
    await db.delete(perm)
    await db.commit()

    await audit_log(db, user, "permission_change", "permission", uuid.UUID(perm_id), detail, request=request)
    return {"message": "已撤销"}
