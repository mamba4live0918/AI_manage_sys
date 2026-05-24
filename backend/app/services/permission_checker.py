import uuid
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select, or_
from app.models import User, File, Permission


async def check_permission(
    db: AsyncSession,
    user: User | None,
    resource_id: uuid.UUID,
    action: str,
) -> bool:
    """5级ACL检查：管理员 → 用户 → 角色 → 部门 → 项目 → 父目录递归继承"""
    if user and user.role == "admin":
        return True

    # 查资源是否存在
    result = await db.execute(select(File).where(File.id == resource_id))
    resource = result.scalar_one_or_none()
    if resource is None:
        return False

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
