import uuid
from fastapi import APIRouter, Depends, HTTPException, status, Request
from pydantic import BaseModel
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select, func
from app.database import get_db
from app.models import User, Department
from app.security import get_current_user
from app.services.audit import log as audit_log

router = APIRouter(prefix="/departments", tags=["departments"])


class CreateDepartmentRequest(BaseModel):
    name: str
    description: str = ""
    accessible_modules: list[str] = []


class UpdateDepartmentRequest(BaseModel):
    name: str | None = None
    description: str | None = None
    accessible_modules: list[str] | None = None


class SetLeaderRequest(BaseModel):
    leader_id: str


class AddMemberRequest(BaseModel):
    user_id: str


def _admin_only(user: User):
    if user.role != "admin":
        raise HTTPException(status_code=403, detail="仅管理员可操作")


def _admin_or_leader(user: User, dept: Department):
    if user.role == "admin":
        return
    if dept.leader_id == user.id:
        return
    raise HTTPException(status_code=403, detail="仅管理员或部门长可操作")


def _department_row(d, members_count: int = 0):
    return {
        "id": str(d.id),
        "name": d.name,
        "description": d.description or "",
        "leader": {
            "id": str(d.leader.id),
            "username": d.leader.username,
            "role": d.leader.role,
        }
        if d.leader
        else None,
        "accessible_modules": d.accessible_modules or [],
        "member_count": members_count,
        "created_at": d.created_at.isoformat() if d.created_at else None,
    }


@router.get("")
async def list_departments(
    db: AsyncSession = Depends(get_db),
    user: User = Depends(get_current_user),
):
    result = await db.execute(select(Department).order_by(Department.created_at))
    depts = result.scalars().all()

    items = []
    for d in depts:
        cnt_result = await db.execute(
            select(func.count()).select_from(User).where(User.department_id == d.id)
        )
        items.append(_department_row(d, cnt_result.scalar() or 0))

    return {"items": items}


@router.post("", status_code=status.HTTP_201_CREATED)
async def create_department(
    body: CreateDepartmentRequest,
    db: AsyncSession = Depends(get_db),
    user: User = Depends(get_current_user),
    request: Request = None,
):
    _admin_only(user)

    existing = await db.execute(
        select(Department).where(Department.name == body.name)
    )
    if existing.scalar_one_or_none():
        raise HTTPException(status_code=400, detail="部门名称已存在")

    dept = Department(name=body.name, description=body.description,
                      accessible_modules=body.accessible_modules)
    db.add(dept)
    await db.commit()
    await db.refresh(dept)
    await audit_log(db, user, "dept_create", "department", dept.id, body.name, request=request)
    return _department_row(dept, 0)


@router.put("/{dept_id}")
async def update_department(
    dept_id: str,
    body: UpdateDepartmentRequest,
    db: AsyncSession = Depends(get_db),
    user: User = Depends(get_current_user),
    request: Request = None,
):
    _admin_only(user)

    result = await db.execute(select(Department).where(Department.id == dept_id))
    dept = result.scalar_one_or_none()
    if not dept:
        raise HTTPException(status_code=404, detail="部门不存在")

    old_name = dept.name
    if body.name is not None:
        dup = await db.execute(
            select(Department).where(
                Department.name == body.name, Department.id != dept_id
            )
        )
        if dup.scalar_one_or_none():
            raise HTTPException(status_code=400, detail="部门名称已存在")
        dept.name = body.name
    if body.description is not None:
        dept.description = body.description
    if body.accessible_modules is not None:
        dept.accessible_modules = body.accessible_modules

    await db.commit()

    cnt_result = await db.execute(
        select(func.count()).select_from(User).where(User.department_id == dept.id)
    )
    await audit_log(db, user, "dept_update", "department", dept.id, dept.name, request=request)
    return _department_row(dept, cnt_result.scalar() or 0)


@router.delete("/{dept_id}")
async def delete_department(
    dept_id: str,
    db: AsyncSession = Depends(get_db),
    user: User = Depends(get_current_user),
    request: Request = None,
):
    _admin_only(user)

    result = await db.execute(select(Department).where(Department.id == dept_id))
    dept = result.scalar_one_or_none()
    if not dept:
        raise HTTPException(status_code=404, detail="部门不存在")

    dept_name = dept.name
    await db.execute(
        User.__table__.update()
        .where(User.department_id == dept_id)
        .values(department_id=None)
    )

    await db.delete(dept)
    await db.commit()
    await audit_log(db, user, "dept_delete", "department", uuid.UUID(dept_id), dept_name, request=request)
    return {"message": "部门已删除，成员已变为未安排"}


@router.patch("/{dept_id}/leader")
async def set_leader(
    dept_id: str,
    body: SetLeaderRequest,
    db: AsyncSession = Depends(get_db),
    user: User = Depends(get_current_user),
    request: Request = None,
):
    _admin_only(user)

    result = await db.execute(select(Department).where(Department.id == dept_id))
    dept = result.scalar_one_or_none()
    if not dept:
        raise HTTPException(status_code=404, detail="部门不存在")

    leader_result = await db.execute(
        select(User).where(User.id == body.leader_id)
    )
    leader = leader_result.scalar_one_or_none()
    if not leader:
        raise HTTPException(status_code=404, detail="用户不存在")

    dept.leader_id = leader.id
    await db.commit()
    await db.refresh(dept)

    cnt_result = await db.execute(
        select(func.count()).select_from(User).where(User.department_id == dept.id)
    )
    await audit_log(db, user, "dept_set_leader", "department", dept.id,
                    f"{dept.name} → {leader.username}", request=request)
    return _department_row(dept, cnt_result.scalar() or 0)


@router.post("/{dept_id}/members")
async def add_member(
    dept_id: str,
    body: AddMemberRequest,
    db: AsyncSession = Depends(get_db),
    user: User = Depends(get_current_user),
    request: Request = None,
):
    result = await db.execute(select(Department).where(Department.id == dept_id))
    dept = result.scalar_one_or_none()
    if not dept:
        raise HTTPException(status_code=404, detail="部门不存在")

    _admin_or_leader(user, dept)

    member_result = await db.execute(
        select(User).where(User.id == body.user_id)
    )
    member = member_result.scalar_one_or_none()
    if not member:
        raise HTTPException(status_code=404, detail="用户不存在")

    member.department_id = uuid.UUID(dept_id)
    member.department = dept.name
    await db.commit()
    await audit_log(db, user, "dept_add_member", "department", dept.id,
                    f"{dept.name} + {member.username}", request=request)
    return {"message": "成员已添加"}


@router.delete("/{dept_id}/members/{user_id}")
async def remove_member(
    dept_id: str,
    user_id: str,
    db: AsyncSession = Depends(get_db),
    user: User = Depends(get_current_user),
    request: Request = None,
):
    result = await db.execute(select(Department).where(Department.id == dept_id))
    dept = result.scalar_one_or_none()
    if not dept:
        raise HTTPException(status_code=404, detail="部门不存在")

    _admin_or_leader(user, dept)

    member_result = await db.execute(
        select(User).where(User.id == user_id)
    )
    member = member_result.scalar_one_or_none()
    if not member:
        raise HTTPException(status_code=404, detail="用户不存在")

    if member.department_id != uuid.UUID(dept_id):
        raise HTTPException(status_code=400, detail="该用户不在此部门")

    member_name = member.username
    member.department_id = None
    member.department = ""
    await db.commit()
    await audit_log(db, user, "dept_remove_member", "department", dept.id,
                    f"{dept.name} - {member_name}", request=request)
    return {"message": "成员已移除"}
