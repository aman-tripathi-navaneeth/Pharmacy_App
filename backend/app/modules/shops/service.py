from datetime import datetime, timezone
from typing import Any

from asyncpg import UniqueViolationError

from app.core.errors import ApiError
from app.db.postgres import get_pg_connection
from app.modules.notifications import service as notifications

SHOP_STATUS_PENDING = "PENDING"
SHOP_STATUS_ACTIVE = "ACTIVE"
SHOP_STATUS_SUSPENDED = "SUSPENDED"

# camelCase API field -> snake_case column (for dynamic UPDATEs).
_UPDATE_COLUMNS = {
    "shopName": "shop_name",
    "address": "address",
    "phoneE164": "phone_e164",
    "emailNormalized": "email_normalized",
    "licenceDetails": "licence_details",
    "paymentSettings": "payment_settings",
    "status": "status",
    "ownerUserId": "owner_user_id",
}


async def create_shop(
    db: Any,
    *,
    shop_name: str,
    address: dict[str, Any],
    phone_e164: str,
    owner_user_id: str,
    created_by: str,
    email_normalized: str | None = None,
    licence_details: dict[str, Any] | None = None,
) -> dict[str, Any]:
    now = datetime.now(timezone.utc)
    pool = await get_pg_connection(db)
    try:
        async with pool.acquire() as conn:
            existing = await conn.fetchrow(
                "SELECT id FROM shops WHERE shop_name = $1 AND owner_user_id = $2",
                shop_name,
                owner_user_id,
            )
            if existing:
                raise ApiError(
                    409,
                    "SHOP_NAME_EXISTS",
                    "A shop with this name already exists for your account",
                )
            row = await conn.fetchrow(
                """INSERT INTO shops
                   (shop_name, owner_user_id, address, phone_e164, status,
                    created_by, created_at, updated_at, email_normalized, licence_details)
                   VALUES ($1, $2, $3::jsonb, $4, $5, $6, $7, $7, $8, $9::jsonb)
                   RETURNING *""",
                shop_name,
                owner_user_id,
                address,
                phone_e164,
                SHOP_STATUS_ACTIVE,
                created_by,
                now,
                email_normalized,
                licence_details,
            )
    except UniqueViolationError:
        raise ApiError(409, "SHOP_NAME_EXISTS", "This shop already exists") from None

    document = dict(row)
    store_id = str(document["id"])
    await notifications.notify(
        db,
        user_id=created_by,
        store_id=store_id,
        title="Shop created",
        message=f"{shop_name} was created successfully.",
        type_="SHOP",
    )
    if owner_user_id and owner_user_id != created_by:
        await notifications.notify(
            db,
            user_id=owner_user_id,
            store_id=store_id,
            title="Welcome to your shop",
            message=f"{shop_name} is ready. Complete your profile setup to get started.",
            type_="PROFILE",
        )
    return document


async def find_by_owner(
    db: Any, owner_user_id: str, store_id: str | None = None
) -> dict[str, Any] | None:
    pool = await get_pg_connection(db)
    async with pool.acquire() as conn:
        if store_id:
            row = await conn.fetchrow(
                "SELECT * FROM shops WHERE id = $1 AND owner_user_id = $2",
                store_id,
                owner_user_id,
            )
        else:
            row = await conn.fetchrow(
                "SELECT * FROM shops WHERE owner_user_id = $1 ORDER BY created_at LIMIT 1",
                owner_user_id,
            )
    return dict(row) if row else None


async def find_by_id(db: Any, store_id: str) -> dict[str, Any]:
    pool = await get_pg_connection(db)
    async with pool.acquire() as conn:
        row = await conn.fetchrow("SELECT * FROM shops WHERE id = $1", store_id)
    if row:
        return dict(row)
    raise ApiError(404, "SHOP_NOT_FOUND", "Shop not found")


async def search_shops(
    db: Any,
    *,
    search: str | None = None,
    status: str | None = None,
    page: int = 1,
    page_size: int = 20,
) -> dict[str, Any]:
    pool = await get_pg_connection(db)
    conditions: list[str] = []
    args: list[Any] = []
    if search and search.strip():
        args.append(f"%{search.strip()}%")
        conditions.append("shop_name ILIKE $" + str(len(args)))
    if status:
        args.append(status)
        conditions.append("status = $" + str(len(args)))
    where = (" WHERE " + " AND ".join(conditions)) if conditions else ""

    async with pool.acquire() as conn:
        count_row = await conn.fetchrow(f"SELECT COUNT(*) AS total FROM shops{where}", *args)
        offset = (page - 1) * page_size
        rows = await conn.fetch(
            f"SELECT * FROM shops{where} ORDER BY created_at DESC OFFSET ${len(args) + 1} LIMIT ${len(args) + 2}",
            *args,
            offset,
            page_size,
        )
    return {
        "items": [dict(row) for row in rows],
        "total": int(count_row["total"]) if count_row else 0,
        "page": page,
        "pageSize": page_size,
    }


async def update_shop(db: Any, store_id: str, patch: dict[str, Any]) -> dict[str, Any]:
    set_parts: list[str] = []
    args: list[Any] = []
    json_columns: set[str] = set()

    for key, value in patch.items():
        column = _UPDATE_COLUMNS.get(key)
        if not column or key in ("ownerUserId", "createdBy"):
            continue
        args.append(value)
        placeholder = f"${len(args)}"
        if key in ("address", "licenceDetails", "paymentSettings"):
            json_columns.add(placeholder)
            set_parts.append(f"{column} = {placeholder}::jsonb")
        else:
            set_parts.append(f"{column} = {placeholder}")

    if not set_parts:
        return await find_by_id(db, store_id)

    args.append(datetime.now(timezone.utc))
    set_parts.append("updated_at = $" + str(len(args)))
    args.append(store_id)

    pool = await get_pg_connection(db)
    async with pool.acquire() as conn:
        try:
            row = await conn.fetchrow(
                f"UPDATE shops SET {', '.join(set_parts)} WHERE id = ${len(args)} RETURNING *",
                *args,
            )
        except UniqueViolationError:
            raise ApiError(
                409, "SHOP_NAME_EXISTS", "A shop with this name already exists"
            ) from None
    if not row:
        raise ApiError(404, "SHOP_NOT_FOUND", "Shop not found")
    return dict(row)


async def set_status(db: Any, store_id: str, status: str) -> dict[str, Any]:
    pool = await get_pg_connection(db)
    row = await pool.fetchrow(
        "UPDATE shops SET status = $1, updated_at = $2 WHERE id = $3 RETURNING *",
        status,
        datetime.now(timezone.utc),
        store_id,
    )
    if not row:
        raise ApiError(404, "SHOP_NOT_FOUND", "Shop not found")
    return dict(row)


async def counts_by_status(db: Any) -> dict[str, int]:
    pool = await get_pg_connection(db)
    row = await pool.fetchrow(
        """SELECT
             COUNT(*) FILTER (WHERE status = 'ACTIVE') AS active,
             COUNT(*) FILTER (WHERE status = 'PENDING') AS pending,
             COUNT(*) FILTER (WHERE status = 'SUSPENDED') AS suspended,
             COUNT(*) AS total
           FROM shops"""
    )
    return {
        "active": int(row["active"]) if row else 0,
        "pending": int(row["pending"]) if row else 0,
        "suspended": int(row["suspended"]) if row else 0,
        "total": int(row["total"]) if row else 0,
    }
