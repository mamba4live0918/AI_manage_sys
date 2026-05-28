"""Unified full-text search API powered by Elasticsearch."""
from fastapi import APIRouter, Depends, Query
from app.models import User
from app.security import get_current_user
from app.services.search import search as es_search

router = APIRouter(prefix="/search", tags=["search"])


@router.get("")
async def unified_search(
    q: str = Query(..., min_length=1, description="Search query"),
    module: str = Query("", description="Filter by module (bidding_knowledge, marketing_knowledge, customers, files, coursewares, contracts)"),
    size: int = Query(20, ge=1, le=100),
    offset: int = Query(0, ge=0),
    user: User = Depends(get_current_user),
):
    dept_id = str(user.department_id) if user.role != "admin" and user.department_id else None
    return await es_search(query=q, module=module, department_id=dept_id, size=size, offset=offset)
