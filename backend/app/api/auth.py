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


class RoleUpdate(BaseModel):
    role: str


class CreateUserRequest(BaseModel):
    username: str
    email: str
    password: str
    role: str = "general"


class UpdateModulesRequest(BaseModel):
    extra_modules: list[str] = []


ALL_MODULES = [
    {"key": "dashboard", "label": "首页", "icon": "home"},
    {"key": "files", "label": "文件", "icon": "folder"},
    {"key": "ip", "label": "讲师IP", "icon": "auto_awesome"},
    {"key": "audit", "label": "审计", "icon": "schedule"},
    {"key": "users", "label": "用户管理", "icon": "people"},
    {"key": "marketing", "label": "市场部", "icon": "campaign"},
    {"key": "bidding", "label": "招投标", "icon": "gavel"},
    {"key": "pm", "label": "项目管理", "icon": "engineering"},
    {"key": "hr", "label": "HR", "icon": "people"},
    {"key": "finance", "label": "财务", "icon": "account_balance"},
]

ALL_MODULE_KEYS = [m["key"] for m in ALL_MODULES]


def _get_accessible_modules(user: User, dept: Department | None = None) -> list[str]:
    if user.role == "admin":
        return ALL_MODULE_KEYS
    modules = set(dept.accessible_modules if dept else [])
    modules.update(user.extra_modules or [])
    if not modules:
        modules.update(["dashboard", "files"])
    # preserve order from ALL_MODULES
    return [k for k in ALL_MODULE_KEYS if k in modules]


def _user_dict(r: User) -> dict:
    return {
        "id": str(r.id),
        "username": r.username,
        "email": r.email,
        "role": r.role,
        "department": r.department or "",
        "department_id": str(r.department_id) if r.department_id else None,
        "extra_modules": r.extra_modules or [],
        "is_active": r.is_active,
        "created_at": r.created_at.isoformat() if r.created_at else None,
    }


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
    # eager load department for module access
    if user.department_id:
        dept_result = await db.execute(
            select(Department).where(Department.id == user.department_id)
        )
        dept = dept_result.scalar_one_or_none()
    else:
        dept = None
    return TokenResponse(
        access_token=token,
        user={
            "id": str(user.id),
            "username": user.username,
            "email": user.email,
            "role": user.role,
            "department": user.department,
            "department_id": str(user.department_id) if user.department_id else None,
            "accessible_modules": _get_accessible_modules(user, dept),
        },
    )


@router.get("/me")
async def me(user: User = Depends(get_current_user), db: AsyncSession = Depends(get_db)):
    if user.department_id:
        dept_result = await db.execute(
            select(Department).where(Department.id == user.department_id)
        )
        dept = dept_result.scalar_one_or_none()
    else:
        dept = None
    return {
        "id": str(user.id),
        "username": user.username,
        "email": user.email,
        "role": user.role,
        "department": user.department,
        "department_id": str(user.department_id) if user.department_id else None,
        "accessible_modules": _get_accessible_modules(user, dept),
        "is_active": user.is_active,
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
            "accessible_modules": d.accessible_modules or [],
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


@router.get("/config/nav")
async def get_nav_config(
    db: AsyncSession = Depends(get_db),
    user: User = Depends(get_current_user),
):
    if user.department_id:
        dept_result = await db.execute(
            select(Department).where(Department.id == user.department_id)
        )
        dept = dept_result.scalar_one_or_none()
    else:
        dept = None
    modules = _get_accessible_modules(user, dept)
    return {
        "modules": [m for m in ALL_MODULES if m["key"] in modules],
    }


@router.get("/modules")
async def list_all_modules(user: User = Depends(get_current_user)):
    return {"modules": ALL_MODULES}


@router.patch("/users/{user_id}/modules")
async def update_user_modules(
    user_id: str,
    body: UpdateModulesRequest,
    db: AsyncSession = Depends(get_db),
    user: User = Depends(get_current_user),
):
    if user.role != "admin":
        raise HTTPException(status_code=403, detail="仅管理员可操作")

    result = await db.execute(select(User).where(User.id == user_id))
    target = result.scalar_one_or_none()
    if not target:
        raise HTTPException(status_code=404, detail="用户不存在")

    target.extra_modules = body.extra_modules
    await db.commit()
    return {"message": "模块权限已更新", "extra_modules": target.extra_modules}
