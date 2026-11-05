"""Suppliers and purchase orders (module 3 + inbound receiving for module 4)."""

import uuid
from datetime import datetime, timezone
from typing import Any

from app.core.errors import ApiError
from app.db.postgres import get_pg_connection
from app.modules.audit import service as audit
from app.modules.inventory.schemas import parse_datetime


async def list_suppliers(db: Any, store_id: str) -> list[dict[str, Any]]:
    pool = await get_pg_connection(db)
    rows = await pool.fetch(
        "SELECT * FROM suppliers WHERE store_id = $1 ORDER BY name", store_id
    )
    return [dict(row) for row in rows]


async def create_supplier(db: Any, store_id: str, payload: dict[str, Any]) -> dict[str, Any]:
    name = str(payload.get("name") or "").strip()
    if not name:
        raise ApiError(400, "VALIDATION_ERROR", "Supplier name is required")
    now = datetime.now(timezone.utc)
    pool = await get_pg_connection(db)
    row = await pool.fetchrow(
        """INSERT INTO suppliers
           (id, store_id, name, contact_name, phone, email, gstin, address, status,
            created_at, updated_at)
           VALUES ($1, $2, $3, $4, $5, $6, $7, $8::jsonb, 'ACTIVE', $9, $9)
           RETURNING *""",
        str(uuid.uuid4()),
        store_id,
        name,
        payload.get("contactName"),
        payload.get("phone"),
        payload.get("email"),
        payload.get("gstin"),
        payload.get("address") or {},
        now,
    )
    return dict(row)


async def find_supplier(db: Any, store_id: str, supplier_id: str) -> dict[str, Any]:
    pool = await get_pg_connection(db)
    row = await pool.fetchrow(
        "SELECT * FROM suppliers WHERE id = $1 AND store_id = $2", supplier_id, store_id
    )
    if row:
        return dict(row)
    raise ApiError(404, "SUPPLIER_NOT_FOUND", "Supplier not found")


async def update_supplier(
    db: Any, store_id: str, supplier_id: str, payload: dict[str, Any]
) -> dict[str, Any]:
    await find_supplier(db, store_id, supplier_id)
    mapping = {
        "name": "name",
        "contactName": "contact_name",
        "phone": "phone",
        "email": "email",
        "gstin": "gstin",
        "status": "status",
    }
    set_parts: list[str] = []
    args: list[Any] = []
    for key, column in mapping.items():
        if key in payload and payload[key] is not None:
            args.append(payload[key])
            set_parts.append(f"{column} = ${len(args)}")
    if "address" in payload and payload["address"] is not None:
        args.append(payload["address"])
        set_parts.append(f"address = ${len(args)}::jsonb")
    if not set_parts:
        return await find_supplier(db, store_id, supplier_id)
    args.extend([datetime.now(timezone.utc), supplier_id, store_id])
    pool = await get_pg_connection(db)
    row = await pool.fetchrow(
        f"""UPDATE suppliers SET {', '.join(set_parts)}, updated_at = ${len(args) - 2}
            WHERE id = ${len(args) - 1} AND store_id = ${len(args)} RETURNING *""",
        *args,
    )
    return dict(row)


async def delete_supplier(
    db: Any, store_id: str, supplier_id: str, actor_id: str | None = None
) -> None:
    """Archive a supplier. Historic purchase orders keep their reference."""
    await find_supplier(db, store_id, supplier_id)
    pool = await get_pg_connection(db)
    await pool.execute(
        """UPDATE suppliers SET status = 'INACTIVE', updated_at = $1
           WHERE id = $2 AND store_id = $3""",
        datetime.now(timezone.utc),
        supplier_id,
        store_id,
    )
    if actor_id:
        await audit.record(
            db,
            actor_user_id=actor_id,
            actor_role="SHOP_OWNER",
            store_id=store_id,
            action="owner.supplier.archive",
            target_type="supplier",
            target_id=supplier_id,
            result="SUCCESS",
        )


async def list_orders(db: Any, store_id: str) -> list[dict[str, Any]]:
    pool = await get_pg_connection(db)
    rows = await pool.fetch(
        """SELECT po.*, s.name AS supplier_name
           FROM purchase_orders po LEFT JOIN suppliers s ON s.id = po.supplier_id
           WHERE po.store_id = $1 ORDER BY po.created_at DESC""",
        store_id,
    )
    return [dict(row) for row in rows]


async def find_order(db: Any, store_id: str, order_id: str) -> dict[str, Any]:
    pool = await get_pg_connection(db)
    row = await pool.fetchrow(
        "SELECT * FROM purchase_orders WHERE id = $1 AND store_id = $2", order_id, store_id
    )
    if not row:
        raise ApiError(404, "PURCHASE_ORDER_NOT_FOUND", "Purchase order not found")
    items = await pool.fetch(
        "SELECT * FROM purchase_order_items WHERE purchase_order_id = $1 ORDER BY medicine_name",
        order_id,
    )
    document = dict(row)
    document["items"] = [dict(item) for item in items]
    return document


async def create_order(
    db: Any, store_id: str, actor_id: str, payload: dict[str, Any]
) -> dict[str, Any]:
    items = payload.get("items") or []
    if not items:
        raise ApiError(400, "VALIDATION_ERROR", "Add at least one purchase order line")
    supplier_id = payload.get("supplierId")
    if supplier_id:
        await find_supplier(db, store_id, str(supplier_id))

    now = datetime.now(timezone.utc)
    order_id = str(uuid.uuid4())
    po_number = payload.get("poNumber") or f"PO-{now:%Y%m%d}-{order_id[:5].upper()}"
    total = 0.0
    prepared: list[dict[str, Any]] = []
    for raw in items:
        name = str(raw.get("medicineName") or "").strip()
        if not name:
            raise ApiError(400, "VALIDATION_ERROR", "Each line needs a medicine name")
        quantity = int(raw.get("quantity") or 0)
        unit_cost = float(raw.get("unitCost") or 0)
        total += quantity * unit_cost
        prepared.append(
            {
                "id": str(uuid.uuid4()),
                "medicine_name": name,
                "barcode": raw.get("barcode"),
                "batch_number": raw.get("batchNumber"),
                "quantity": quantity,
                "unit_cost": unit_cost,
                "expiry_date": raw.get("expiryDate"),
            }
        )

    pool = await get_pg_connection(db)
    async with pool.acquire() as conn:
        async with conn.transaction():
            row = await conn.fetchrow(
                """INSERT INTO purchase_orders
                   (id, store_id, supplier_id, po_number, status, expected_date, notes,
                    total, created_by, created_at, updated_at)
                   VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $10)
                   RETURNING *""",
                order_id,
                store_id,
                supplier_id or None,
                po_number,
                "ORDERED",
                payload.get("expectedDate"),
                payload.get("notes"),
                round(total, 2),
                actor_id or None,
                now,
            )
            for line in prepared:
                await conn.execute(
                    """INSERT INTO purchase_order_items
                       (id, purchase_order_id, medicine_name, barcode, batch_number,
                        quantity, unit_cost, expiry_date)
                       VALUES ($1, $2, $3, $4, $5, $6, $7, $8)""",
                    line["id"],
                    order_id,
                    line["medicine_name"],
                    line["barcode"],
                    line["batch_number"],
                    line["quantity"],
                    line["unit_cost"],
                    line["expiry_date"],
                )
    document = dict(row)
    document["items"] = prepared
    await audit.record(
        db,
        actor_user_id=actor_id,
        actor_role="SHOP_OWNER",
        store_id=store_id,
        action="owner.purchase_order.create",
        target_type="purchase_order",
        target_id=order_id,
        result="SUCCESS",
    )
    return document


async def update_order(
    db: Any,
    store_id: str,
    actor_id: str,
    order_id: str,
    payload: dict[str, Any],
) -> dict[str, Any]:
    """Update a purchase order (status, expected date, notes)."""
    order = await find_order(db, store_id, order_id)
    status = str(payload.get("status") or "").upper()
    allowed = ("ORDERED", "RECEIVED", "CANCELLED")
    if status and status not in allowed:
        raise ApiError(400, "INVALID_STATUS", "status must be ORDERED, RECEIVED or CANCELLED")
    if status == "CANCELLED" and order["status"] == "RECEIVED":
        raise ApiError(400, "ALREADY_RECEIVED", "A received order cannot be cancelled")
    if status == "RECEIVED" and order["status"] == "RECEIVED":
        raise ApiError(400, "ALREADY_RECEIVED", "This purchase order was already received")

    set_parts: list[str] = []
    args: list[Any] = []
    if status:
        args.append(status)
        set_parts.append(f"status = ${len(args)}")
    if payload.get("expectedDate") is not None:
        args.append(str(payload["expectedDate"]))
        set_parts.append(f"expected_date = ${len(args)}")
    if payload.get("notes") is not None:
        args.append(str(payload["notes"]))
        set_parts.append(f"notes = ${len(args)}")
    if not set_parts:
        return order

    args.extend([datetime.now(timezone.utc), order_id, store_id])
    pool = await get_pg_connection(db)
    await pool.execute(
        f"""UPDATE purchase_orders SET {', '.join(set_parts)}, updated_at = ${len(args) - 2}
            WHERE id = ${len(args) - 1} AND store_id = ${len(args)}""",
        *args,
    )
    await audit.record(
        db,
        actor_user_id=actor_id,
        actor_role="SHOP_OWNER",
        store_id=store_id,
        action="owner.purchase_order.update",
        target_type="purchase_order",
        target_id=order_id,
        result="SUCCESS",
    )
    return await find_order(db, store_id, order_id)


async def delete_order(
    db: Any, store_id: str, actor_id: str, order_id: str
) -> None:
    """Delete a purchase order that was never received."""
    order = await find_order(db, store_id, order_id)
    if order["status"] == "RECEIVED":
        raise ApiError(
            400,
            "ALREADY_RECEIVED",
            "A received order added stock and cannot be deleted",
        )
    pool = await get_pg_connection(db)
    await pool.execute(
        "DELETE FROM purchase_orders WHERE id = $1 AND store_id = $2", order_id, store_id
    )
    await audit.record(
        db,
        actor_user_id=actor_id,
        actor_role="SHOP_OWNER",
        store_id=store_id,
        action="owner.purchase_order.delete",
        target_type="purchase_order",
        target_id=order_id,
        result="SUCCESS",
    )


async def receive_order(
    db: Any, store_id: str, actor_id: str, order_id: str
) -> dict[str, Any]:
    """Inward: add every PO line to stock and mark the order received."""
    order = await find_order(db, store_id, order_id)
    if order["status"] == "RECEIVED":
        raise ApiError(400, "ALREADY_RECEIVED", "This purchase order was already received")

    now = datetime.now(timezone.utc)
    pool = await get_pg_connection(db)
    received = 0
    async with pool.acquire() as conn:
        async with conn.transaction():
            for line in order["items"]:
                quantity = int(line["quantity"] or 0)
                if quantity <= 0:
                    continue
                barcode = line.get("barcode") or f"PO-{order['po_number']}"
                batch = line.get("batch_number") or f"PO-{now:%y%m%d}"
                existing = await conn.fetchrow(
                    """SELECT id, quantity FROM inventory_items
                       WHERE store_id = $1 AND barcode = $2 AND batch_number = $3""",
                    store_id,
                    barcode,
                    batch,
                )
                if existing:
                    await conn.execute(
                        """UPDATE inventory_items
                           SET quantity = quantity + $1, updated_at = $2,
                               selling_price = CASE WHEN $3 > 0 THEN $3 ELSE selling_price END
                           WHERE id = $4""",
                        quantity,
                        now,
                        float(line["unit_cost"] or 0),
                        existing["id"],
                    )
                    item_id = existing["id"]
                else:
                    expiry = parse_datetime(line["expiry_date"]) if line.get("expiry_date") else None
                    item_id = await conn.fetchval(
                        """INSERT INTO inventory_items
                           (store_id, medicine_name, barcode, batch_number, expiry_date,
                            quantity, selling_price, reorder_level, created_by,
                            created_at, updated_at)
                           VALUES ($1, $2, $3, $4, $5, $6, $7, 10, $8, $9, $9)
                           RETURNING id""",
                        store_id,
                        line["medicine_name"],
                        barcode,
                        batch,
                        expiry,
                        quantity,
                        float(line["unit_cost"] or 0),
                        actor_id or None,
                        now,
                    )
                await conn.execute(
                    """INSERT INTO stock_movements
                       (store_id, item_id, movement_type, quantity, reason, created_by, created_at)
                       VALUES ($1, $2, 'IN', $3, $4, $5, $6)""",
                    store_id,
                    item_id,
                    quantity,
                    f"Purchase order {order['po_number']}",
                    actor_id or None,
                    now,
                )
                received += 1
            await conn.execute(
                "UPDATE purchase_orders SET status = 'RECEIVED', updated_at = $1 WHERE id = $2",
                now,
                order_id,
            )

    await audit.record(
        db,
        actor_user_id=actor_id,
        actor_role="SHOP_OWNER",
        store_id=store_id,
        action="owner.purchase_order.receive",
        target_type="purchase_order",
        target_id=order_id,
        result="SUCCESS",
    )
    return {
        "purchaseOrderId": order_id,
        "linesReceived": received,
        "status": "RECEIVED",
    }
