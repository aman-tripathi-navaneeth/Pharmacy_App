from datetime import datetime, timezone
from typing import Any

from fastapi import APIRouter, Depends

from app.common.deps import get_current_user, get_db
from app.common.identity import is_probably_email, normalize_email, normalize_phone
from app.core.errors import ApiError
from app.db.serialize import serialize
from app.modules.audit import service as audit
from app.modules.auth.schemas import UpdateShopIn
from app.modules.shops import service
from app.modules.users import service as users

router = APIRouter(prefix="/shops", tags=["Shops"])


@router.get("/me")
async def my_shop(
    user: dict[str, Any] = Depends(get_current_user),
    db: Any = Depends(get_db),
) -> Any:
    owner = await users.find_by_id(db, str(user["sub"]))
    shop = await service.find_by_owner(db, str(user["sub"]), str(user.get("storeId") or ""))
    return serialize({"user": users.sanitize_user(owner), "shop": shop})


@router.patch("/{store_id}")
async def update_my_shop(
    store_id: str,
    payload: UpdateShopIn,
    user: dict[str, Any] = Depends(get_current_user),
    db: Any = Depends(get_db),
) -> Any:
    owner = await users.find_by_id(db, str(user["sub"]))
    if str(owner.get("owner_store_id") or "") != store_id:
        raise ApiError(403, "SHOP_ACCESS_DENIED", "You cannot access another shop")

    shop = await service.find_by_owner(db, str(user["sub"]), store_id)
    if not shop:
        return {"message": "Shop not accessible"}

    patch: dict[str, Any] = {}
    if payload.shopName:
        patch["shopName"] = payload.shopName.strip()
    if payload.addressLine1 or payload.city or payload.state or payload.postalCode:
        current = shop.get("address") or {}
        patch["address"] = {
            "line1": payload.addressLine1 or current.get("line1") or "",
            "line2": payload.addressLine2 if payload.addressLine2 is not None else current.get("line2"),
            "city": payload.city or current.get("city") or "",
            "state": payload.state or current.get("state") or "",
            "postalCode": payload.postalCode or current.get("postalCode") or "",
            "country": current.get("country") or "India",
        }
    if payload.phone and not is_probably_email(payload.phone):
        patch["phoneE164"] = normalize_phone(payload.phone)
    if payload.email and is_probably_email(payload.email):
        patch["emailNormalized"] = normalize_email(payload.email)
    if payload.paymentSettings is not None:
        settings = payload.paymentSettings
        patch["paymentSettings"] = {
            "upiId": settings.upiId,
            "payeeName": settings.payeeName,
            "qrImage": settings.qrImage,
            "cashEnabled": settings.cashEnabled,
            "onlineEnabled": settings.onlineEnabled,
        }
    patch["updatedAt"] = datetime.now(timezone.utc)

    updated = await service.update_shop(db, store_id, patch)
    await audit.record(
        db,
        actor_user_id=str(user["sub"]),
        actor_role=str(user.get("role") or "UNKNOWN"),
        store_id=store_id,
        action="owner.shop.update",
        target_type="shop",
        target_id=store_id,
        result="SUCCESS",
    )
    return serialize({"shop": updated})
