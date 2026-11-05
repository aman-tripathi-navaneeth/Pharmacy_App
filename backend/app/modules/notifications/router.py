from typing import Any

from fastapi import APIRouter, Depends
from pydantic import BaseModel, Field

from app.common.deps import get_current_user, get_db
from app.db.serialize import serialize
from app.modules.notifications import service

router = APIRouter(prefix="/notifications", tags=["Notifications"])


class WhatsAppIn(BaseModel):
    to: str = Field(min_length=6, max_length=20)
    message: str = Field(min_length=1, max_length=1000)


@router.post("/whatsapp")
async def send_whatsapp(
    payload: WhatsAppIn,
    user: dict[str, Any] = Depends(get_current_user),
    db: Any = Depends(get_db),
) -> dict[str, Any]:
    """Queue a WhatsApp message.

    No delivery provider is configured yet, so the message is stored as an
    in-app notification and reported back as queued-in-app only. Wiring a real
    provider (Meta Cloud API / Twilio) only needs replacing this delivery step.
    """
    await service.notify(
        db,
        user_id=str(user["sub"]),
        store_id=user.get("storeId"),
        title=f"WhatsApp to {payload.to}",
        message=payload.message,
        type_="WHATSAPP",
    )
    return {
        "status": "QUEUED",
        "channel": "WHATSAPP",
        "delivery": "IN_APP_ONLY",
        "recipient": payload.to,
    }


@router.get("")
async def list_notifications(
    user: dict[str, Any] = Depends(get_current_user),
    db: Any = Depends(get_db),
) -> Any:
    return serialize({"items": await service.list_notifications(db, str(user["sub"]))})


@router.get("/unread-count")
async def unread_count(
    user: dict[str, Any] = Depends(get_current_user),
    db: Any = Depends(get_db),
) -> dict[str, int]:
    return {"count": await service.unread_count(db, str(user["sub"]))}


@router.get("/action-required")
async def action_required(
    user: dict[str, Any] = Depends(get_current_user),
    db: Any = Depends(get_db),
) -> Any:
    """Steps the signed-in user still has to complete."""
    items = await service.action_required(db, user)
    return serialize({"items": items, "count": len(items)})


@router.post("/read-all")
async def mark_all_read(
    user: dict[str, Any] = Depends(get_current_user),
    db: Any = Depends(get_db),
) -> dict[str, int]:
    return await service.mark_all_read(db, str(user["sub"]))


@router.post("/{notification_id}/read")
async def mark_read(
    notification_id: str,
    user: dict[str, Any] = Depends(get_current_user),
    db: Any = Depends(get_db),
) -> dict[str, str]:
    await service.mark_read(db, str(user["sub"]), notification_id)
    return {"message": "Notification marked as read"}


@router.delete("/{notification_id}")
async def delete_notification(
    notification_id: str,
    user: dict[str, Any] = Depends(get_current_user),
    db: Any = Depends(get_db),
) -> dict[str, str]:
    await service.delete_notification(db, str(user["sub"]), notification_id)
    return {"message": "Notification removed"}
