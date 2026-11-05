from datetime import datetime, timezone
from typing import Any

from app.common.identity import is_probably_email, normalize_email, normalize_phone
from app.core.errors import ApiError
from app.db.postgres import get_pg_connection
from app.modules.audit import service as audit
from app.modules.shops import service as shops
from app.modules.users import service as users


def steps(user: dict[str, Any]) -> dict[str, Any]:
    must_change = user.get("must_change_password", user.get("mustChangePassword"))
    verified = user.get("phone_verified_at", user.get("phoneVerifiedAt")) or user.get(
        "email_verified_at", user.get("emailVerifiedAt")
    )
    profile_done = user.get("profile_completed_at", user.get("profileCompletedAt")) and user.get(
        "onboarding_completed_at", user.get("onboardingCompletedAt")
    )
    items = [
        {"key": "change_password", "done": not bool(must_change)},
        {"key": "verify_contact", "done": bool(verified)},
        {"key": "complete_profile", "done": bool(profile_done)},
    ]
    return {
        "mustChangePassword": bool(must_change),
        "steps": items,
        "allDone": all(item["done"] for item in items),
    }


async def status(db: Any, user_id: str) -> dict[str, Any]:
    return steps(await users.find_by_id(db, user_id))


async def update_profile(
    db: Any,
    user_id: str,
    store_id: str | None,
    payload: dict[str, Any],
) -> dict[str, Any]:
    if not store_id:
        raise ApiError(403, "FORBIDDEN_ROLE", "Owners only")

    user = await users.find_by_id(db, user_id)
    if user.get("must_change_password"):
        raise ApiError(400, "ONBOARDING_BLOCKED", "Change your temporary password first")
    if not (user.get("phone_verified_at") or user.get("email_verified_at")):
        raise ApiError(400, "ONBOARDING_BLOCKED", "Verify your contact details first")
    if user.get("profile_completed_at"):
        raise ApiError(400, "ALREADY_COMPLETED", "Profile already completed")

    shop_contact = str(payload["shopContactNumber"])
    email = normalize_email(shop_contact) if is_probably_email(shop_contact) else None
    phone = None if email else normalize_phone(shop_contact)

    await users.update_profile_fields(db, user_id, {"fullName": payload["fullName"]})

    shop = await shops.find_by_owner(db, user_id, store_id)
    if not shop:
        raise ApiError(400, "SHOP_NOT_FOUND", "Shop not found")

    patch: dict[str, Any] = {
        "shopName": payload["shopName"],
        "address": {
            "line1": payload["addressLine1"],
            "line2": payload.get("addressLine2"),
            "city": payload["city"],
            "state": payload["state"],
            "postalCode": payload["postalCode"],
            "country": (shop.get("address") or {}).get("country") or "India",
        },
    }
    if email:
        patch["emailNormalized"] = email
    elif phone:
        patch["phoneE164"] = phone
    await shops.update_shop(db, store_id, patch)

    now = datetime.now(timezone.utc)
    pool = await get_pg_connection(db)
    await pool.execute(
        """UPDATE users
           SET profile_completed_at = $1, onboarding_completed_at = $1, updated_at = $1
           WHERE id = $2""",
        now,
        user_id,
    )
    user.update({"profile_completed_at": now, "onboarding_completed_at": now})

    await audit.record(
        db,
        actor_user_id=user_id,
        actor_role=str(user.get("role") or "UNKNOWN"),
        store_id=store_id,
        action="owner.profile.complete",
        target_type="user",
        target_id=user_id,
        result="SUCCESS",
    )
    return {"user": users.sanitize_user(user), "onboarding": steps(user)}


async def complete_lite(db: Any, user_id: str, store_id: str | None, payload: dict[str, Any]) -> dict[str, Any]:
    """Accept the mobile screen's shorter payload and normalize it."""
    user = await users.find_by_id(db, user_id)
    shop = await shops.find_by_owner(db, user_id, store_id or "") if store_id else None
    address = (shop or {}).get("address") or {}
    shop_address = str(payload.get("shopAddress") or "").strip()

    full_payload = {
        "fullName": payload.get("fullName") or user.get("full_name") or "",
        "shopName": payload["shopName"],
        "addressLine1": payload.get("addressLine1") or shop_address or address.get("line1") or "Not provided",
        "addressLine2": payload.get("addressLine2") or address.get("line2"),
        "city": payload.get("city") or address.get("city") or "Not provided",
        "state": payload.get("state") or address.get("state") or "Not provided",
        "postalCode": payload.get("postalCode") or address.get("postalCode") or "00000",
        "shopContactNumber": payload.get("shopContactNumber")
        or (shop or {}).get("phone_e164")
        or user.get("phone_e164")
        or user.get("email_normalized"),
    }
    if not full_payload["shopContactNumber"]:
        raise ApiError(400, "NO_CONTACT_ON_FILE", "No contact details found to verify")
    return await update_profile(db, user_id, store_id, full_payload)
