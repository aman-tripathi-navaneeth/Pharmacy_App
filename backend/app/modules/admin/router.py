from datetime import datetime, timezone
from typing import Any

from fastapi import APIRouter, Depends, Query

from app.common.deps import get_db, require_roles
from app.common.export import build_snapshot
from app.common.identity import is_probably_email, normalize_email, normalize_phone
from app.core.config import get_settings
from app.db.serialize import serialize
from app.modules.audit import service as audit
from app.modules.auth import service as auth
from app.modules.auth.schemas import CreateShopIn, RecoveryIn, ShopStatusIn, UpdateShopIn
from app.modules.email import service as email_service
from app.modules.notifications import service as notifications
from app.modules.shops import service as shops
from app.modules.users import service as users

router = APIRouter(prefix="/admin", tags=["Admin"])
admin_only = require_roles("SUPER_ADMIN")


def _address(dto: CreateShopIn | UpdateShopIn, fallback_country: str | None = None) -> dict[str, Any]:
    return {
        "line1": getattr(dto, "addressLine1", None),
        "line2": getattr(dto, "addressLine2", None),
        "city": getattr(dto, "city", None),
        "state": getattr(dto, "state", None),
        "postalCode": getattr(dto, "postalCode", None),
        "country": fallback_country or "India",
    }


@router.post("/shops", status_code=201)
async def create_shop(
    payload: CreateShopIn,
    admin: dict[str, Any] = Depends(admin_only),
    db: Any = Depends(get_db),
) -> Any:
    settings = get_settings()
    owner_email = normalize_email(payload.ownerContact) if is_probably_email(payload.ownerContact) else None
    owner_phone = None if is_probably_email(payload.ownerContact) else normalize_phone(payload.ownerContact)
    await users.assert_unique_contact(db, owner_email, owner_phone)

    shop_phone = None if is_probably_email(payload.shopPhone) else normalize_phone(payload.shopPhone)
    if is_probably_email(payload.shopPhone):
        shop_email = normalize_email(payload.shopPhone)
    elif payload.shopEmail and is_probably_email(payload.shopEmail):
        shop_email = normalize_email(payload.shopEmail)
    else:
        shop_email = None

    temp_password = auth.generate_temp_password()
    owner = await users.create_owner(
        db,
        full_name=payload.ownerFullName.strip(),
        email_normalized=owner_email,
        phone_e164=owner_phone,
        password_hash=auth.hash_password(temp_password),
    )

    shop = await shops.create_shop(
        db,
        shop_name=payload.shopName.strip(),
        address=_address(payload),
        phone_e164=shop_phone or payload.shopPhone.strip(),
        email_normalized=shop_email,
        licence_details=(
            {
                "type": "DRUG_LICENCE",
                "number": payload.licenceNumber,
                "issuingAuthority": payload.licenceAuthority,
            }
            if payload.licenceNumber or payload.licenceAuthority
            else None
        ),
        owner_user_id=str(owner["id"]),
        created_by=str(admin["sub"]),
    )

    await users.update_owner_store(db, str(owner["id"]), str(shop["id"]))
    await notifications.send_owner_invite(owner_phone or owner_email or "contact", temp_password)
    # Send the credentials to the owner's own inbox so the account can be used
    # straight away. The email attempt is logged even when no address exists.
    await email_service.send_credentials_email(
        db,
        to_email=owner_email,
        recipient_name=payload.ownerFullName.strip(),
        temp_password=temp_password,
        login_hint=payload.ownerContact.strip(),
        shop_name=payload.shopName.strip(),
        store_id=str(shop["id"]),
        user_id=str(owner["id"]),
        reason="Your pharmacy account has been created",
    )
    await audit.record(
        db,
        actor_user_id=str(admin["sub"]),
        actor_role=str(admin.get("role") or "UNKNOWN"),
        store_id=str(shop["id"]),
        action="admin.shops.create",
        target_type="shop",
        target_id=str(shop["id"]),
        result="SUCCESS",
    )
    owner = await users.find_by_id(db, str(owner["id"]))
    response: dict[str, Any] = {
        "shop": shop,
        "owner": users.sanitize_user(owner),
        "activationStatus": (
            "DEVELOPMENT_CREDENTIAL" if settings.is_development else "DELIVERY_NOT_CONFIGURED"
        ),
    }
    if settings.is_development:
        response["devTempPassword"] = temp_password
    return serialize(response)


@router.get("/shops")
async def list_shops(
    search: str | None = Query(default=None),
    status: str | None = Query(default=None),
    page: str | None = Query(default=None),
    pageSize: str | None = Query(default=None),
    _admin: dict[str, Any] = Depends(admin_only),
    db: Any = Depends(get_db),
) -> Any:
    try:
        parsed_page = max(1, int(page or "1"))
    except ValueError:
        parsed_page = 1
    try:
        parsed_size = int(pageSize or "20")
    except ValueError:
        parsed_size = 20
    size = min(50, max(1, parsed_size))
    status_filter = status if status in ("PENDING", "ACTIVE", "SUSPENDED") else None
    return serialize(
        await shops.search_shops(
            db,
            search=search,
            status=status_filter,
            page=parsed_page,
            page_size=size,
        )
    )


@router.get("/shops/{store_id}")
async def get_shop(
    store_id: str,
    _admin: dict[str, Any] = Depends(admin_only),
    db: Any = Depends(get_db),
) -> Any:
    shop = await shops.find_by_id(db, store_id)
    owner_id = str(shop.get("owner_user_id") or "")
    owner = await users.find_by_id(db, owner_id) if owner_id else None
    return serialize({"shop": shop, "owner": users.sanitize_user(owner)})


@router.patch("/shops/{store_id}")
async def update_shop(
    store_id: str,
    payload: UpdateShopIn,
    admin: dict[str, Any] = Depends(admin_only),
    db: Any = Depends(get_db),
) -> Any:
    patch: dict[str, Any] = {}
    if payload.shopName:
        patch["shopName"] = payload.shopName.strip()
    if payload.addressLine1 or payload.city or payload.state or payload.postalCode:
        current = await shops.find_by_id(db, store_id)
        address = current.get("address") or {}
        patch["address"] = {
            "line1": payload.addressLine1 or address.get("line1") or "",
            "line2": payload.addressLine2 if payload.addressLine2 is not None else address.get("line2"),
            "city": payload.city or address.get("city") or "",
            "state": payload.state or address.get("state") or "",
            "postalCode": payload.postalCode or address.get("postalCode") or "",
            "country": address.get("country") or "India",
        }
    if payload.phone and not is_probably_email(payload.phone):
        patch["phoneE164"] = normalize_phone(payload.phone)
    if payload.email and is_probably_email(payload.email):
        patch["emailNormalized"] = normalize_email(payload.email)
    patch["updatedAt"] = datetime.now(timezone.utc)

    shop = await shops.update_shop(db, store_id, patch)
    await audit.record(
        db,
        actor_user_id=str(admin["sub"]),
        actor_role=str(admin.get("role") or "UNKNOWN"),
        store_id=store_id,
        action="admin.shops.update",
        target_type="shop",
        target_id=store_id,
        result="SUCCESS",
    )
    return serialize({"shop": shop})


@router.patch("/shops/{store_id}/status")
async def set_status(
    store_id: str,
    payload: ShopStatusIn,
    admin: dict[str, Any] = Depends(admin_only),
    db: Any = Depends(get_db),
) -> Any:
    shop = await shops.set_status(db, store_id, payload.status)
    if payload.status == "SUSPENDED":
        owner_id = str(shop.get("owner_user_id") or "")
        if owner_id:
            owner = await users.find_by_id(db, owner_id)
            await email_service.send_action_required_email(
                db,
                to_email=owner.get("email_normalized"),
                recipient_name=str(owner.get("full_name") or "there"),
                action_title="Your shop was suspended",
                action_message=(
                    "The admin suspended this shop account. Contact support to get it "
                    "reactivated before you can continue billing."
                ),
                shop_name=str(shop.get("shop_name") or "your pharmacy"),
                store_id=store_id,
                user_id=owner_id,
            )
    await audit.record(
        db,
        actor_user_id=str(admin["sub"]),
        actor_role=str(admin.get("role") or "UNKNOWN"),
        store_id=store_id,
        action="admin.shops.status",
        target_type="shop",
        target_id=store_id,
        result="SUCCESS",
    )
    return serialize({"shop": shop})


@router.post("/shops/{store_id}/reissue-access")
async def reissue_access(
    store_id: str,
    admin: dict[str, Any] = Depends(admin_only),
    db: Any = Depends(get_db),
) -> Any:
    settings = get_settings()
    shop = await shops.find_by_id(db, store_id)
    result = await auth.issue_recovery_credential(
        db, str(shop.get("owner_user_id") or ""), str(admin["sub"]), str(admin.get("role") or "")
    )
    await audit.record(
        db,
        actor_user_id=str(admin["sub"]),
        actor_role=str(admin.get("role") or "UNKNOWN"),
        store_id=store_id,
        action="admin.shops.reissue_access",
        target_type="user",
        target_id=str(shop.get("owner_user_id") or ""),
        result="SUCCESS",
    )
    response: dict[str, Any] = {"shop": shop, "destination": result["destination"]}
    if settings.is_development:
        response["devTempPassword"] = result["tempPassword"]
    return serialize(response)


@router.post("/users/{user_id}/recovery")
async def recovery(
    user_id: str,
    payload: RecoveryIn | None = None,
    admin: dict[str, Any] = Depends(admin_only),
    db: Any = Depends(get_db),
) -> Any:
    settings = get_settings()
    result = await auth.issue_recovery_credential(
        db,
        user_id,
        str(admin["sub"]),
        str(admin.get("role") or ""),
        payload.newTempPassword if payload else None,
    )
    response: dict[str, Any] = {"destination": result["destination"]}
    if settings.is_development:
        response["devTempPassword"] = result["tempPassword"]
    return serialize(response)


@router.get("/export")
async def export_data(
    _admin: dict[str, Any] = Depends(admin_only),
    db: Any = Depends(get_db),
) -> Any:
    """Download a redacted JSON snapshot of every project collection (PostgreSQL)."""
    settings = get_settings()
    database = settings.DATABASE_URL.split("/")[-1] if settings.DATABASE_URL else "unknown"
    snapshot = await build_snapshot(db, database)
    snapshot["note"] = "PostgreSQL-based snapshot"
    return serialize(snapshot)


@router.delete("/shops/{store_id}")
async def delete_shop(
    store_id: str,
    _admin: dict[str, Any] = Depends(admin_only),
) -> dict[str, str]:
    # Shops are never hard-deleted; stock/ledger protection per repo rules.
    return {"message": "Shops are archived, not deleted. Use status update to suspend."}


@router.get("/stats")
async def stats(
    _admin: dict[str, Any] = Depends(admin_only),
    db: Any = Depends(get_db),
) -> dict[str, int]:
    return await shops.counts_by_status(db)
