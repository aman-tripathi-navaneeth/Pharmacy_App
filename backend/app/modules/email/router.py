"""Email history and SMTP administration endpoints."""

from typing import Any

from fastapi import APIRouter, Depends, Query
from pydantic import BaseModel, Field

from app.common.deps import get_current_user, get_db, require_roles
from app.core.errors import ApiError
from app.db.serialize import serialize
from app.modules.email import service

router = APIRouter(prefix="/emails", tags=["Email"])
admin_only = require_roles("SUPER_ADMIN")


class TestEmailIn(BaseModel):
    to: str = Field(min_length=5, max_length=160)


@router.get("")
async def list_emails(
    status: str | None = Query(default=None, max_length=24),
    template: str | None = Query(default=None, max_length=48),
    limit: int = Query(default=100, ge=1, le=200),
    user: dict[str, Any] = Depends(get_current_user),
    db: Any = Depends(get_db),
) -> Any:
    """Every email the signed-in user is allowed to see, newest first."""
    items = await service.list_email_logs(
        db, user=user, status=status, template=template, limit=limit
    )
    return serialize({"items": items})


@router.get("/status")
async def email_status(
    _user: dict[str, Any] = Depends(get_current_user),
) -> Any:
    """Non-secret SMTP configuration so the settings screen can show it."""
    return serialize(service.smtp_status())


@router.get("/{email_id}")
async def get_email(
    email_id: str,
    user: dict[str, Any] = Depends(get_current_user),
    db: Any = Depends(get_db),
) -> Any:
    log = await service.find_email_log(db, email_id)
    if not log:
        raise ApiError(404, "EMAIL_NOT_FOUND", "Email not found")
    if user.get("role") != "SUPER_ADMIN":
        own_user = str(log.get("recipient_user_id") or "")
        own_store = str(log.get("store_id") or "")
        if own_user != str(user.get("sub") or "") and own_store != str(
            user.get("storeId") or ""
        ):
            raise ApiError(403, "EMAIL_ACCESS_DENIED", "You cannot view this email")
    return serialize({"email": log})


@router.post("/{email_id}/resend")
async def resend_email(
    email_id: str,
    _admin: dict[str, Any] = Depends(admin_only),
    db: Any = Depends(get_db),
) -> Any:
    log = await service.find_email_log(db, email_id)
    if not log:
        raise ApiError(404, "EMAIL_NOT_FOUND", "Email not found")
    updated = await service.resend_email(db, log)
    return serialize({"email": updated})


@router.post("/test")
async def send_test_email(
    payload: TestEmailIn,
    admin: dict[str, Any] = Depends(admin_only),
    db: Any = Depends(get_db),
) -> Any:
    record = await service.send_test_email(
        db, to_email=payload.to.strip(), user_id=str(admin.get("sub") or "")
    )
    return serialize({"email": record})
