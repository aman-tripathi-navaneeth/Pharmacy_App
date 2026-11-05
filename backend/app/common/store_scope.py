from typing import Any

from app.core.errors import ApiError
from app.modules.shops import service as shops
from app.modules.users.service import object_id


async def resolve_store_id(db: Any, user: dict[str, Any], requested_store_id: str | None) -> str:
    if user.get("role") == "SHOP_OWNER":
        own_store = str(user.get("storeId") or "")
        # Reject an explicit attempt to use another shop instead of silently
        # substituting the owner's shop. This keeps the contract explicit and
        # makes cross-shop probes fail loudly.
        if requested_store_id and requested_store_id != own_store:
            raise ApiError(403, "SHOP_ACCESS_DENIED", "You cannot access another shop")
        store_id = own_store
    else:
        store_id = str(requested_store_id or "")
    if not store_id or not object_id(store_id):
        raise ApiError(400, "SHOP_REQUIRED", "Choose a valid shop before continuing")
    await shops.find_by_id(db, store_id)
    return store_id
