from datetime import datetime, timezone
from typing import Any

from app.db.postgres import get_pg_connection


async def record(
    db: Any,
    *,
    actor_user_id: str,
    actor_role: str,
    action: str,
    target_type: str,
    result: str = "SUCCESS",
    store_id: str | None = None,
    target_id: str | None = None,
    ip_address: str | None = None,
    request_id: str | None = None,
) -> None:
    """Record an audit log entry using PostgreSQL."""
    now = datetime.now(timezone.utc)
    pool = await get_pg_connection(db)
    await pool.execute(
        """INSERT INTO audit_logs
           (actor_user_id, actor_role, action, target_type, target_id, store_id,
            result, ip_address, request_id, created_at, updated_at)
           VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $10)""",
        actor_user_id or None,
        actor_role,
        action,
        target_type,
        str(target_id) if target_id else None,
        store_id or None,
        result,
        ip_address,
        request_id,
        now,
    )


async def list_for(
    db: Any,
    *,
    user_id: str | None = None,
    action: str | None = None,
    limit: int = 100,
) -> list[dict[str, Any]]:
    pool = await get_pg_connection(db)
    query = "SELECT * FROM audit_logs WHERE 1=1"
    args: list[Any] = []
    if user_id:
        args.append(user_id)
        query += " AND actor_user_id = $" + str(len(args))
    if action:
        args.append(action)
        query += " AND action = $" + str(len(args))
    args.append(limit)
    query += " ORDER BY created_at DESC LIMIT $" + str(len(args))
    rows = await pool.fetch(query, *args)
    return [dict(row) for row in rows]
