import uuid
from datetime import datetime, timezone
from typing import Any

from app.common.identity import is_probably_email, normalize_email, normalize_phone
from app.core.errors import ApiError
from app.db.postgres import get_pg_connection

USER_ROLE_SUPER_ADMIN = "SUPER_ADMIN"
USER_ROLE_SHOP_OWNER = "SHOP_OWNER"
USER_STATUS_INVITED = "INVITED"
USER_STATUS_ACTIVE = "ACTIVE"

# camelCase API field -> snake_case column.
_PROFILE_COLUMNS = {
    "fullName": "full_name",
    "language": "language",
    "plan": "plan",
    "profileImage": "profile_image",
    "planStartedAt": "plan_started_at",
    "planExpiresAt": "plan_expires_at",
    "planPaymentStatus": "plan_payment_status",
    "mustChangePassword": "must_change_password",
    "passwordHash": "password_hash",
    "status": "status",
}


def object_id(value: str | uuid.UUID | None) -> str | None:
    """Normalise a PostgreSQL UUID primary key to its canonical string form."""
    if isinstance(value, uuid.UUID):
        return str(value)
    if not value:
        return None
    try:
        return str(uuid.UUID(str(value)))
    except (ValueError, TypeError, AttributeError):
        return None


def sanitize_user(doc: dict[str, Any] | None) -> dict[str, Any]:
    if not doc:
        return {}
    copy = dict(doc)
    copy.pop("password_hash", None)
    copy.pop("passwordHash", None)
    return copy


async def find_by_id(db: Any, user_id: str) -> dict[str, Any]:
    oid = object_id(user_id)
    if not oid:
        raise ApiError(404, "USER_NOT_FOUND", "User not found")
    pool = await get_pg_connection(db)
    async with pool.acquire() as conn:
        row = await conn.fetchrow("SELECT * FROM users WHERE id = $1", oid)
    if not row:
        raise ApiError(404, "USER_NOT_FOUND", "User not found")
    return dict(row)


async def find_by_identifier(db: Any, identifier: str) -> dict[str, Any] | None:
    raw = identifier.strip()
    if is_probably_email(raw):
        return await find_by_email(db, normalize_email(raw))
    return await find_by_phone(db, normalize_phone(raw))


async def find_by_email(db: Any, email: str) -> dict[str, Any] | None:
    pool = await get_pg_connection(db)
    async with pool.acquire() as conn:
        row = await conn.fetchrow(
            "SELECT * FROM users WHERE email_normalized = $1", normalize_email(email)
        )
    return dict(row) if row else None


async def find_by_phone(db: Any, phone: str) -> dict[str, Any] | None:
    pool = await get_pg_connection(db)
    async with pool.acquire() as conn:
        row = await conn.fetchrow(
            "SELECT * FROM users WHERE phone_e164 = $1", normalize_phone(phone)
        )
    return dict(row) if row else None


async def assert_unique_contact(
    db: Any,
    email: str | None = None,
    phone: str | None = None,
    except_user_id: str | None = None,
) -> None:
    conditions: list[str] = []
    args: list[Any] = []
    if email:
        args.append(normalize_email(email))
        conditions.append("email_normalized = $" + str(len(args)))
    if phone:
        args.append(normalize_phone(phone))
        conditions.append("phone_e164 = $" + str(len(args)))
    if not conditions:
        return

    except_oid = object_id(except_user_id)
    query = "SELECT id FROM users WHERE (" + " OR ".join(conditions) + ")"
    if except_oid:
        args.append(except_oid)
        query += " AND id != $" + str(len(args))

    pool = await get_pg_connection(db)
    async with pool.acquire() as conn:
        rows = await conn.fetch(query, *args)
    if rows:
        raise ApiError(
            409, "IDENTITY_ALREADY_EXISTS", "This email or phone is already registered"
        )


async def update_profile_fields(db: Any, user_id: str, patch: dict[str, Any]) -> dict[str, Any]:
    oid = object_id(user_id)
    if not oid:
        raise ApiError(404, "USER_NOT_FOUND", "User not found")

    set_parts: list[str] = []
    args: list[Any] = []
    for key, value in patch.items():
        column = _PROFILE_COLUMNS.get(key)
        if not column:
            continue
        args.append(value)
        set_parts.append(f"{column} = ${len(args)}")
    if not set_parts:
        return await find_by_id(db, oid)

    args.append(datetime.now(timezone.utc))
    set_parts.append("updated_at = $" + str(len(args)))
    args.append(oid)
    query = f"UPDATE users SET {', '.join(set_parts)} WHERE id = ${len(args)} RETURNING *"

    pool = await get_pg_connection(db)
    async with pool.acquire() as conn:
        row = await conn.fetchrow(query, *args)
    if not row:
        raise ApiError(404, "USER_NOT_FOUND", "User not found")
    return dict(row)


async def create_owner(
    db: Any,
    *,
    full_name: str,
    password_hash: str,
    email_normalized: str | None = None,
    phone_e164: str | None = None,
    status: str = USER_STATUS_INVITED,
    must_change_password: bool = True,
) -> dict[str, Any]:
    now = datetime.now(timezone.utc)
    pool = await get_pg_connection(db)
    async with pool.acquire() as conn:
        row = await conn.fetchrow(
            """INSERT INTO users
               (full_name, role, password_hash, status, must_change_password,
                email_normalized, phone_e164, created_at, updated_at)
               VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9)
               RETURNING *""",
            full_name,
            USER_ROLE_SHOP_OWNER,
            password_hash,
            status,
            must_change_password,
            email_normalized,
            phone_e164,
            now,
            now,
        )
    return dict(row)


async def update_owner_store(db: Any, user_id: str, store_id: str) -> None:
    pool = await get_pg_connection(db)
    await pool.execute(
        "UPDATE users SET owner_store_id = $1, updated_at = $2 WHERE id = $3",
        store_id,
        datetime.now(timezone.utc),
        user_id,
    )


async def set_password(
    db: Any,
    user_id: str,
    password_hash: str,
    *,
    must_change_password: bool,
) -> dict[str, Any]:
    pool = await get_pg_connection(db)
    row = await pool.fetchrow(
        """UPDATE users
           SET password_hash = $1, must_change_password = $2, updated_at = $3
           WHERE id = $4 RETURNING *""",
        password_hash,
        must_change_password,
        datetime.now(timezone.utc),
        user_id,
    )
    if not row:
        raise ApiError(404, "USER_NOT_FOUND", "User not found")
    return dict(row)


async def mark_contact_verified(db: Any, user_id: str, *, use_email: bool) -> dict[str, Any]:
    now = datetime.now(timezone.utc)
    column = "email_verified_at" if use_email else "phone_verified_at"
    pool = await get_pg_connection(db)
    row = await pool.fetchrow(
        f"UPDATE users SET {column} = $1, updated_at = $1 WHERE id = $2 RETURNING *",
        now,
        user_id,
    )
    if not row:
        raise ApiError(404, "USER_NOT_FOUND", "User not found")
    return dict(row)


async def touch_last_login(db: Any, user_id: str) -> None:
    pool = await get_pg_connection(db)
    await pool.execute(
        "UPDATE users SET last_login_at = $1 WHERE id = $2",
        datetime.now(timezone.utc),
        user_id,
    )
