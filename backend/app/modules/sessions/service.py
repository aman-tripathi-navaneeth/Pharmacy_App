import secrets
from datetime import datetime, timedelta, timezone
from typing import Any

from app.common.security import random_token, sha256
from app.core.errors import ApiError
from app.db.postgres import get_pg_connection


async def create_session(
    db: Any,
    user_id: str,
    store_id: str | None,
    ttl_days: int,
    device_label: str | None = None,
) -> tuple[str, str]:
    """Create a session and return (raw refresh token, session id)."""
    raw = random_token()
    now = datetime.now(timezone.utc)
    pool = await get_pg_connection(db)
    row = await pool.fetchrow(
        """INSERT INTO sessions
           (user_id, store_id, refresh_token_hash, token_family_id, device_label,
            expires_at, created_at, updated_at)
           VALUES ($1, $2, $3, $4, $5, $6, $7, $7)
           RETURNING id""",
        user_id,
        store_id or None,
        sha256(raw),
        secrets.token_hex(12),
        device_label,
        now + timedelta(days=ttl_days),
        now,
    )
    return raw, str(row["id"])


async def rotate(db: Any, raw_refresh_token: str) -> dict[str, Any]:
    """Validate + rotate a refresh token. Reuse revokes the whole family."""
    pool = await get_pg_connection(db)
    now = datetime.now(timezone.utc)
    async with pool.acquire() as conn:
        doc = await conn.fetchrow(
            "SELECT * FROM sessions WHERE refresh_token_hash = $1",
            sha256(raw_refresh_token),
        )
        if not doc or doc["revoked_at"] or doc["expires_at"] < now:
            if doc and doc["revoked_at"]:
                await conn.execute(
                    """UPDATE sessions SET revoked_at = $1, updated_at = $1
                       WHERE token_family_id = $2 AND revoked_at IS NULL""",
                    now,
                    doc["token_family_id"],
                )
            raise ApiError(401, "SESSION_INVALID", "Session expired, please sign in again")

        new_raw = random_token()
        updated = await conn.fetchrow(
            """UPDATE sessions
               SET refresh_token_hash = $1, last_used_at = $2, updated_at = $2
               WHERE id = $3 RETURNING *""",
            sha256(new_raw),
            now,
            doc["id"],
        )
    result = dict(updated or doc)
    result["newRawToken"] = new_raw
    return result


async def revoke_session(db: Any, session_id: str | None) -> None:
    if not session_id:
        return
    pool = await get_pg_connection(db)
    await pool.execute(
        """UPDATE sessions SET revoked_at = $1, updated_at = $1
           WHERE id = $2 AND revoked_at IS NULL""",
        datetime.now(timezone.utc),
        session_id,
    )


async def revoke_all_for_user(db: Any, user_id: str) -> None:
    pool = await get_pg_connection(db)
    now = datetime.now(timezone.utc)
    await pool.execute(
        """UPDATE sessions SET revoked_at = $1, updated_at = $1
           WHERE user_id = $2 AND revoked_at IS NULL""",
        now,
        user_id,
    )


async def revoke_all_for_user_excluding(
    db: Any, user_id: str, except_session_id: str | None = None
) -> None:
    pool = await get_pg_connection(db)
    now = datetime.now(timezone.utc)
    if except_session_id:
        await pool.execute(
            """UPDATE sessions SET revoked_at = $1, updated_at = $1
               WHERE user_id = $2 AND revoked_at IS NULL AND id != $3""",
            now,
            user_id,
            except_session_id,
        )
    else:
        await revoke_all_for_user(db, user_id)


async def list_active_for_user(db: Any, user_id: str) -> list[dict[str, Any]]:
    pool = await get_pg_connection(db)
    rows = await pool.fetch(
        """SELECT * FROM sessions
           WHERE user_id = $1 AND revoked_at IS NULL AND expires_at > $2
           ORDER BY created_at DESC LIMIT 100""",
        user_id,
        datetime.now(timezone.utc),
    )
    return [dict(row) for row in rows]
