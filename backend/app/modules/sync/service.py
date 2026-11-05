"""Offline sync helpers (module 12).

The client can queue stock adjustments while offline and push them later. Every
operation carries a ``clientRef`` so replaying the same queue never double
applies a movement.
"""

from datetime import datetime, timezone
from typing import Any

from app.core.errors import ApiError
from app.db.postgres import get_pg_connection
from app.modules.inventory import service as inventory


async def state(db: Any, store_id: str) -> dict[str, Any]:
    pool = await get_pg_connection(db)
    counts = {}
    for table, column in (
        ("inventory_items", "store_id"),
        ("bills", "store_id"),
        ("customers", "store_id"),
        ("prescriptions", "shop_id"),
        ("notifications", "store_id"),
    ):
        row = await pool.fetchrow(
            f"SELECT COUNT(*) AS total FROM {table} WHERE {column} = $1", store_id
        )
        counts[table] = int(row["total"]) if row else 0
    return {
        "serverTime": datetime.now(timezone.utc),
        "storeId": store_id,
        "counts": counts,
        "schemaVersion": 1,
    }


async def push(db: Any, store_id: str, actor_id: str, operations: list[dict[str, Any]]) -> dict[str, Any]:
    pool = await get_pg_connection(db)
    applied = 0
    skipped: list[dict[str, Any]] = []
    errors: list[dict[str, Any]] = []

    for index, op in enumerate(operations):
        client_ref = str(op.get("clientRef") or "").strip()
        if not client_ref:
            errors.append({"index": index, "code": "MISSING_CLIENT_REF", "message": "clientRef is required"})
            continue
        existing = await pool.fetchval(
            "SELECT id FROM stock_movements WHERE client_ref = $1 AND store_id = $2",
            client_ref,
            store_id,
        )
        if existing:
            skipped.append({"index": index, "clientRef": client_ref, "reason": "ALREADY_APPLIED"})
            continue
        kind = str(op.get("kind") or "inventory_adjust")
        if kind != "inventory_adjust":
            errors.append({"index": index, "code": "UNSUPPORTED_OPERATION", "message": f"Unsupported kind {kind}"})
            continue
        item_id = str(op.get("itemId") or "")
        movement_type = str(op.get("type") or "").upper()
        quantity = int(op.get("quantity") or 0)
        try:
            await inventory.adjust_stock(
                db,
                store_id,
                actor_id,
                item_id,
                movement_type,
                quantity,
                op.get("reason"),
                client_ref=client_ref,
            )
            applied += 1
        except ApiError as exc:
            errors.append({"index": index, "code": exc.code, "message": exc.message})
    return {"applied": applied, "skipped": skipped, "errors": errors}
