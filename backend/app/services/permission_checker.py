import uuid
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select, or_
from app.models import User, File, Permission
from app.config import settings


async def check_permission(
    db: AsyncSession,
    user: User | None,
    resource_id: uuid.UUID,
    action: str,
) -> bool:
    if user and user.role == "admin":
        return True

    # 查资源是否存在
    result = await db.execute(select(File).where(File.id == resource_id))
    resource = result.scalar_one_or_none()
    if resource is None:
        return False

    # 文件上传者始终可访问自己的文件
    if user and resource.uploaded_by == user.id:
        return True

    # 部门长可访问本部门成员的文件
    if user and resource.uploaded_by is not None:
        from app.models import Department
        from sqlalchemy import select
        dept_result = await db.execute(
            select(Department)
            .join(User, Department.id == User.department_id)
            .where(
                Department.leader_id == user.id,
                User.id == resource.uploaded_by,
            )
        )
        if dept_result.scalar_one_or_none():
            return True

    # 保密级别准入：用户级别 ≥ 文件级别即放行
    user_level = settings.ROLE_CLEARANCE.get(user.role if user else "", 0)
    file_level = resource.confidentiality_level or 0
    if user_level >= file_level:
        return True

    # 级别不够时，回退到显式 ACL（逐文件授权可覆盖保密级限制）
    # 递归收集所有可检查的 resource_id（自身+所有祖先目录）
    ids_to_check = [resource_id]
    current_id = resource.parent_id
    while current_id:
        ids_to_check.append(current_id)
        parent_result = await db.execute(select(File.parent_id).where(File.id == current_id))
        current_id = parent_result.scalar_one_or_none()

    # 构造授权者条件
    grantee_conditions = []
    if user:
        grantee_conditions.append(
            (Permission.grantee_type == "user") & (Permission.grantee_value == str(user.id))
        )
        grantee_conditions.append(
            (Permission.grantee_type == "role") & (Permission.grantee_value == user.role)
        )
        if user.department:
            grantee_conditions.append(
                (Permission.grantee_type == "department") & (Permission.grantee_value == user.department)
            )

    if not grantee_conditions:
        return False

    # 查询：任一ancestor有匹配权限即通过
    query = (
        select(Permission)
        .where(
            Permission.resource_id.in_(ids_to_check),
            Permission.action == action,
            or_(*grantee_conditions),
        )
        .limit(1)
    )
    result = await db.execute(query)
    return result.scalar_one_or_none() is not None
