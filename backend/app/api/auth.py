from fastapi import APIRouter, Depends, HTTPException, status
from pydantic import BaseModel, EmailStr
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select, func
from app.database import get_db
from app.models import User, Department
from app.security import hash_password, verify_password, create_access_token, get_current_user

router = APIRouter(prefix="/auth", tags=["auth"])


class RegisterRequest(BaseModel):
    username: str
    email: str
    password: str


class LoginRequest(BaseModel):
    username: str
    password: str


class TokenResponse(BaseModel):
    access_token: str
    token_type: str = "bearer"
    user: dict


class UserResponse(BaseModel):
    id: str
    username: str
    email: str
    role: str
    department: str
    is_active: bool

    model_config = {"from_attributes": True}


@router.post("/register", status_code=status.HTTP_201_CREATED)
async def register(body: RegisterRequest, db: AsyncSession = Depends(get_db)):
    existing = await db.execute(
        select(User).where((User.username == body.username) | (User.email == body.email))
    )
    if existing.scalar_one_or_none():
        raise HTTPException(status_code=400, detail="用户名或邮箱已存在")

    user = User(
        username=body.username,
        email=body.email,
        hashed_password=hash_password(body.password),
    )
    db.add(user)
    await db.commit()
    await db.refresh(user)
    return {"message": "注册成功", "user_id": str(user.id)}


@router.post("/login")
async def login(body: LoginRequest, db: AsyncSession = Depends(get_db)):
    result = await db.execute(select(User).where(User.username == body.username))
    user = result.scalar_one_or_none()
    if not user or not verify_password(body.password, user.hashed_password):
        raise HTTPException(status_code=401, detail="用户名或密码错误")
    if not user.is_active:
        raise HTTPException(status_code=403, detail="账号已被禁用")

    token = create_access_token({"sub": str(user.id), "role": user.role})
    return TokenResponse(
        access_token=token,
        user={
            "id": str(user.id),
            "username": user.username,
            "email": user.email,
            "role": user.role,
            "department": user.department,
        },
    )


@router.get("/me")
async def me(user: User = Depends(get_current_user)):
    return {
        "id": str(user.id),
        "username": user.username,
        "email": user.email,
        "role": user.role,
        "department": user.department,
        "is_active": user.is_active,
    }


class RoleUpdate(BaseModel):
    role: str


class CreateUserRequest(BaseModel):
    username: str
    email: str
    password: str
    role: str = "general"


def _user_dict(r: User) -> dict:
    return {
        "id": str(r.id),
        "username": r.username,
        "email": r.email,
        "role": r.role,
        "department": r.department or "",
        "department_id": str(r.department_id) if r.department_id else None,
        "is_active": r.is_active,
        "created_at": r.created_at.isoformat() if r.created_at else None,
    }


@router.get("/users")
async def list_users(
    db: AsyncSession = Depends(get_db),
    user: User = Depends(get_current_user),
):
    if user.role != "admin":
        raise HTTPException(status_code=403, detail="仅管理员可查看用户列表")

    result = await db.execute(select(User).order_by(User.created_at.desc()))
    all_users = result.scalars().all()

    dept_result = await db.execute(select(Department).order_by(Department.created_at))
    all_depts = dept_result.scalars().all()

    dept_users: dict[str, list] = {str(d.id): [] for d in all_depts}
    unassigned = []

    for u in all_users:
        ud = _user_dict(u)
        if u.department_id and str(u.department_id) in dept_users:
            dept_users[str(u.department_id)].append(ud)
        else:
            unassigned.append(ud)

    departments = []
    for d in all_depts:
        departments.append({
            "id": str(d.id),
            "name": d.name,
            "description": d.description or "",
            "leader": {
                "id": str(d.leader.id),
                "username": d.leader.username,
                "role": d.leader.role,
            } if d.leader else None,
            "members": dept_users.get(str(d.id), []),
            "member_count": len(dept_users.get(str(d.id), [])),
            "created_at": d.created_at.isoformat() if d.created_at else None,
        })

    return {
        "departments": departments,
        "unassigned": unassigned,
    }


@router.patch("/users/{user_id}/role")
async def update_user_role(
    user_id: str,
    body: RoleUpdate,
    db: AsyncSession = Depends(get_db),
    user: User = Depends(get_current_user),
):
    if user.role != "admin":
        raise HTTPException(status_code=403, detail="仅管理员可修改用户角色")

    if body.role not in ("admin", "dept_manager", "project_manager", "general"):
        raise HTTPException(status_code=400, detail="无效的角色")

    result = await db.execute(select(User).where(User.id == user_id))
    target = result.scalar_one_or_none()
    if not target:
        raise HTTPException(status_code=404, detail="用户不存在")

    target.role = body.role
    await db.commit()
    return {"message": "角色已更新", "role": target.role}


@router.post("/users", status_code=status.HTTP_201_CREATED)
async def create_user(
    body: CreateUserRequest,
    db: AsyncSession = Depends(get_db),
    user: User = Depends(get_current_user),
):
    if user.role != "admin":
        raise HTTPException(status_code=403, detail="仅管理员可创建用户")

    existing = await db.execute(
        select(User).where((User.username == body.username) | (User.email == body.email))
    )
    if existing.scalar_one_or_none():
        raise HTTPException(status_code=400, detail="用户名或邮箱已存在")

    if body.role not in ("admin", "dept_manager", "project_manager", "general"):
        raise HTTPException(status_code=400, detail="无效的角色")

    new_user = User(
        username=body.username,
        email=body.email,
        hashed_password=hash_password(body.password),
        role=body.role,
    )
    db.add(new_user)
    await db.commit()
    await db.refresh(new_user)
    return {"message": "用户已创建", "user_id": str(new_user.id)}


@router.delete("/users/{user_id}")
async def delete_user(
    user_id: str,
    db: AsyncSession = Depends(get_db),
    user: User = Depends(get_current_user),
):
    if user.role != "admin":
        raise HTTPException(status_code=403, detail="仅管理员可删除用户")

    if str(user.id) == user_id:
        raise HTTPException(status_code=400, detail="不能删除自己")

    result = await db.execute(select(User).where(User.id == user_id))
    target = result.scalar_one_or_none()
    if not target:
        raise HTTPException(status_code=404, detail="用户不存在")

    await db.delete(target)
    await db.commit()
    return {"message": "用户已删除"}
