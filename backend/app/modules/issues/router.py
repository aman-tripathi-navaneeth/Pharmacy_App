"""Issues router: owners report, super admin monitors and resolves."""

from typing import Any

from fastapi import APIRouter, Depends, Query
from pydantic import BaseModel, Field

from app.common.deps import get_current_user, get_db, require_roles
from app.db.serialize import serialize
from app.modules.issues import service

router = APIRouter(prefix="/issues", tags=["Issues"])
admin_only = require_roles("SUPER_ADMIN")


class CreateIssueIn(BaseModel):
    title: str = Field(min_length=4, max_length=120)
    description: str = Field(min_length=4, max_length=2000)
    category: str | None = Field(default=None, max_length=32)


class IssueStatusIn(BaseModel):
    status: str = Field(min_length=2, max_length=24)
    note: str | None = Field(default=None, max_length=500)


@router.post("", status_code=201)
async def create_issue(
    payload: CreateIssueIn,
    user: dict[str, Any] = Depends(get_current_user),
    db: Any = Depends(get_db),
) -> Any:
    issue = await service.create_issue(
        db,
        actor=user,
        title=payload.title,
        description=payload.description,
        category=payload.category,
    )
    return serialize({"issue": issue})


@router.get("")
async def list_issues(
    status: str | None = Query(default=None),
    storeId: str | None = Query(default=None),
    user: dict[str, Any] = Depends(get_current_user),
    db: Any = Depends(get_db),
) -> Any:
    items = await service.list_issues(db, user, status=status, store_id=storeId)
    return serialize({"items": items})


@router.patch("/{issue_id}/status")
async def update_issue_status(
    issue_id: str,
    payload: IssueStatusIn,
    admin: dict[str, Any] = Depends(admin_only),
    db: Any = Depends(get_db),
) -> Any:
    issue = await service.update_status(
        db,
        issue_id,
        payload.status,
        payload.note,
        str(admin.get("sub") or admin.get("_id")),
    )
    return serialize({"issue": issue})
