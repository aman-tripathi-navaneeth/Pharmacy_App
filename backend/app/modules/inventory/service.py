import io
import logging
import re
import uuid
from datetime import datetime, timedelta, timezone
from typing import Any

from asyncpg import UniqueViolationError

from app.core.errors import ApiError
from app.db.postgres import get_pg_connection
from app.modules.audit import service as audit
from app.modules.inventory.schemas import parse_datetime
from app.modules.inventory import templates as tpl
from app.modules.notifications import service as notifications

SHOP_STATUS_ACTIVE = "ACTIVE"

logger = logging.getLogger("pharmacy.inventory")


def _normalize(payload: dict[str, Any]) -> dict[str, Any]:
    return {
        "medicine_name": str(payload.get("medicineName") or "").strip(),
        "barcode": str(payload.get("barcode") or "").strip(),
        "batch_number": str(payload.get("batchNumber") or "").strip(),
        "expiry_at": parse_datetime(payload["expiryDate"]) if payload.get("expiryDate") else None,
        "quantity": int(payload.get("quantity") or 0),
        "selling_price": float(payload.get("sellingPrice") or 0),
        "reorder_level": int(payload.get("reorderLevel") or 10),
    }


async def _insert_item(
    db: Any,
    store_id: str,
    actor_id: str,
    payload: dict[str, Any],
    *,
    batch_fallback: str | None = None,
) -> dict[str, Any]:
    data = _normalize(payload)
    if not data["medicine_name"]:
        raise ApiError(400, "VALIDATION_ERROR", "Medicine name is required")
    if not data["batch_number"]:
        data["batch_number"] = batch_fallback or datetime.now(timezone.utc).strftime("B%y%m%d-T")
    now = datetime.now(timezone.utc)
    pool = await get_pg_connection(db)
    try:
        async with pool.acquire() as conn:
            async with conn.transaction():
                row = await conn.fetchrow(
                    """INSERT INTO inventory_items
                       (store_id, medicine_name, barcode, batch_number, expiry_date, quantity,
                        selling_price, reorder_level, created_by, archived, created_at, updated_at)
                       VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, FALSE, $10, $10)
                       RETURNING *""",
                    store_id,
                    data["medicine_name"],
                    data["barcode"],
                    data["batch_number"],
                    data["expiry_at"],
                    data["quantity"],
                    data["selling_price"],
                    data["reorder_level"],
                    actor_id or None,
                    now,
                )
                if data["quantity"] > 0:
                    await conn.execute(
                        """INSERT INTO stock_movements
                           (store_id, item_id, movement_type, quantity, reason,
                            created_by, created_at)
                           VALUES ($1, $2, 'IN', $3, 'Opening stock', $4, $5)""",
                        store_id,
                        row["id"],
                        data["quantity"],
                        actor_id or None,
                        now,
                    )
    except UniqueViolationError:
        raise ApiError(
            409,
            "DUPLICATE_INVENTORY_BATCH",
            "This barcode and batch already exist for the shop",
        ) from None
    return dict(row)


async def _audit(db: Any, store_id: str, actor_id: str, action: str, target_id: str) -> None:
    await audit.record(
        db,
        actor_user_id=actor_id,
        actor_role="SHOP_OWNER",
        store_id=store_id,
        action=action,
        target_type="inventory_item",
        target_id=target_id,
        result="SUCCESS",
    )


async def list_items(db: Any, store_id: str, search: str | None = None) -> list[dict[str, Any]]:
    pool = await get_pg_connection(db)
    query = "SELECT * FROM inventory_items WHERE store_id = $1 AND archived = FALSE"
    args: list[Any] = [store_id]
    if search and search.strip():
        args.append(f"%{search.strip()}%")
        query += (
            " AND (medicine_name ILIKE $" + str(len(args))
            + " OR barcode ILIKE $" + str(len(args))
            + " OR batch_number ILIKE $" + str(len(args)) + ")"
        )
    query += " ORDER BY medicine_name"
    rows = await pool.fetch(query, *args)
    return [dict(row) for row in rows]


async def create_item(
    db: Any,
    store_id: str,
    actor_id: str,
    payload: dict[str, Any],
) -> dict[str, Any]:
    document = await _insert_item(db, store_id, actor_id, payload)
    await notifications.notify(
        db,
        user_id=actor_id,
        store_id=store_id,
        title="Inventory item added",
        message=f"{document['medicine_name']} (batch {document['batch_number']}) added to stock.",
        type_="INVENTORY",
    )
    await _audit(db, store_id, actor_id, "owner.inventory.create", str(document["id"]))
    return document


async def bulk_create_items(
    db: Any,
    store_id: str,
    actor_id: str,
    items: list[dict[str, Any]],
) -> dict[str, Any]:
    created = 0
    failed: list[dict[str, Any]] = []
    for index, payload in enumerate(items):
        try:
            await _insert_item(db, store_id, actor_id, payload, batch_fallback=f"B{index + 1:02d}")
            created += 1
        except ApiError as exc:
            failed.append({"index": index, "code": exc.code, "message": exc.message})
        except Exception as exc:  # keep the batch going, report the row
            logger.exception("bulk inventory row failed")
            failed.append({"index": index, "code": "ERROR", "message": str(exc)})

    if created:
        await _audit(db, store_id, actor_id, "owner.inventory.bulk_create", "bulk")
        await notifications.notify(
            db,
            user_id=actor_id,
            store_id=store_id,
            title="Bulk inventory added",
            message=f"{created} medicine line(s) added to stock.",
            type_="INVENTORY",
        )
    return {"created": created, "failed": failed}


async def find_item(db: Any, store_id: str, item_id: str) -> dict[str, Any]:
    pool = await get_pg_connection(db)
    row = await pool.fetchrow(
        "SELECT * FROM inventory_items WHERE id = $1 AND store_id = $2 AND archived = FALSE",
        item_id,
        store_id,
    )
    if row:
        return dict(row)
    raise ApiError(404, "INVENTORY_ITEM_NOT_FOUND", "Inventory item not found")


async def update_item(
    db: Any,
    store_id: str,
    actor_id: str,
    item_id: str,
    payload: dict[str, Any],
) -> dict[str, Any]:
    await find_item(db, store_id, item_id)
    mapping = {
        "medicineName": ("medicine_name", str),
        "barcode": ("barcode", str),
        "batchNumber": ("batch_number", str),
        "quantity": ("quantity", int),
        "sellingPrice": ("selling_price", float),
        "reorderLevel": ("reorder_level", int),
    }
    set_parts: list[str] = []
    args: list[Any] = []
    for key, (column, caster) in mapping.items():
        if key not in payload or payload[key] is None:
            continue
        args.append(caster(payload[key]))
        set_parts.append(f"{column} = ${len(args)}")
    if payload.get("expiryDate"):
        args.append(parse_datetime(payload["expiryDate"]))
        set_parts.append("expiry_date = $" + str(len(args)))

    if not set_parts:
        return await find_item(db, store_id, item_id)

    args.append(datetime.now(timezone.utc))
    set_parts.append("updated_at = $" + str(len(args)))
    args.extend([item_id, store_id])
    pool = await get_pg_connection(db)
    try:
        row = await pool.fetchrow(
            f"""UPDATE inventory_items SET {', '.join(set_parts)}
                WHERE id = ${len(args) - 1} AND store_id = ${len(args)} RETURNING *""",
            *args,
        )
    except UniqueViolationError:
        raise ApiError(
            409, "DUPLICATE_INVENTORY_BATCH", "This barcode and batch already exist"
        ) from None
    if not row:
        raise ApiError(404, "INVENTORY_ITEM_NOT_FOUND", "Inventory item not found")
    await _audit(db, store_id, actor_id, "owner.inventory.update", item_id)
    return dict(row)


async def archive_item(db: Any, store_id: str, actor_id: str, item_id: str) -> None:
    await find_item(db, store_id, item_id)
    pool = await get_pg_connection(db)
    await pool.execute(
        "UPDATE inventory_items SET archived = TRUE, updated_at = $1 WHERE id = $2 AND store_id = $3",
        datetime.now(timezone.utc),
        item_id,
        store_id,
    )
    await _audit(db, store_id, actor_id, "owner.inventory.archive", item_id)


async def adjust_stock(
    db: Any,
    store_id: str,
    actor_id: str,
    item_id: str,
    movement_type: str,
    quantity: int,
    reason: str | None = None,
    *,
    client_ref: str | None = None,
) -> dict[str, Any]:
    kind = (movement_type or "").strip().upper()
    if kind not in ("IN", "OUT"):
        raise ApiError(400, "INVALID_MOVEMENT", "Movement type must be IN or OUT")
    if quantity < 1:
        raise ApiError(400, "VALIDATION_ERROR", "Quantity must be at least 1")

    now = datetime.now(timezone.utc)
    delta = quantity if kind == "IN" else -quantity
    pool = await get_pg_connection(db)
    async with pool.acquire() as conn:
        async with conn.transaction():
            row = await conn.fetchrow(
                """UPDATE inventory_items
                   SET quantity = quantity + $1, updated_at = $2
                   WHERE id = $3 AND store_id = $4 AND quantity + $1 >= 0
                   RETURNING *""",
                delta,
                now,
                item_id,
                store_id,
            )
            if row is None:
                current_quantity = await conn.fetchval(
                    "SELECT quantity FROM inventory_items WHERE id = $1 AND store_id = $2 AND archived = FALSE",
                    item_id,
                    store_id,
                )
                if current_quantity is None:
                    raise ApiError(404, "INVENTORY_ITEM_NOT_FOUND", "Inventory item not found")
                raise ApiError(
                    400,
                    "INSUFFICIENT_STOCK",
                    f"Only {current_quantity} left",
                )
            await conn.execute(
                """INSERT INTO stock_movements
                   (store_id, item_id, movement_type, quantity, reason, created_by,
                    client_ref, created_at)
                   VALUES ($1, $2, $3, $4, $5, $6, $7, $8)""",
                store_id,
                item_id,
                kind,
                quantity,
                reason,
                actor_id or None,
                client_ref,
                now,
            )
    await _audit(db, store_id, actor_id, f"owner.inventory.{kind.lower()}", item_id)
    return dict(row)


async def list_movements(db: Any, store_id: str, item_id: str) -> list[dict[str, Any]]:
    pool = await get_pg_connection(db)
    rows = await pool.fetch(
        """SELECT movement.*,
                  SUM(CASE WHEN movement_type = 'IN' THEN quantity ELSE -quantity END)
                    OVER (ORDER BY created_at, id) AS balance_after
           FROM stock_movements AS movement
           WHERE store_id = $1 AND item_id = $2
           ORDER BY created_at DESC, id DESC LIMIT 100""",
        store_id,
        item_id,
    )
    return [dict(row) for row in rows]


async def stock_summary(db: Any, store_id: str) -> dict[str, Any]:
    pool = await get_pg_connection(db)
    row = await pool.fetchrow(
        """SELECT
             COUNT(*) AS total_items,
             COALESCE(SUM(quantity), 0) AS total_units,
             COALESCE(SUM(quantity * selling_price), 0) AS stock_value,
             COUNT(*) FILTER (WHERE quantity <= reorder_level) AS low_stock,
             COUNT(*) FILTER (WHERE expiry_date IS NOT NULL AND expiry_date < NOW() + INTERVAL '30 days') AS expiring_30,
             COUNT(*) FILTER (WHERE expiry_date IS NOT NULL AND expiry_date < NOW() + INTERVAL '90 days') AS expiring_90
           FROM inventory_items
           WHERE store_id = $1 AND archived = FALSE""",
        store_id,
    )
    return {
        "totalItems": int(row["total_items"]) if row else 0,
        "totalUnits": int(row["total_units"]) if row else 0,
        "stockValue": round(float(row["stock_value"]), 2) if row else 0.0,
        "lowStock": int(row["low_stock"]) if row else 0,
        "expiring30": int(row["expiring_30"]) if row else 0,
        "expiring90": int(row["expiring_90"]) if row else 0,
    }


async def import_template(
    db: Any,
    store_id: str,
    actor_id: str,
    *,
    template_id: str,
    selling_price: float | None = None,
    batch_number: str | None = None,
    default_quantity: int = 0,
    expiry_months_ahead: int = 12,
    barcode_overrides: dict[str, str] | None = None,
    selected_barcodes: list[str] | None = None,
) -> dict[str, Any]:
    template = tpl.get_template(template_id)
    if template is None:
        raise ApiError(400, "TEMPLATE_NOT_FOUND", "Unknown inventory template")

    now = datetime.now(timezone.utc)
    expiry = now + timedelta(days=30 * int(expiry_months_ahead or 12))
    batch = batch_number or now.strftime("TPL-%y%m%d")
    selected = set(selected_barcodes or [])
    overrides = barcode_overrides or {}

    created = 0
    skipped: list[dict[str, Any]] = []
    for item in template.items:
        if selected and item.barcode not in selected:
            continue
        barcode = overrides.get(item.barcode) or item.barcode
        try:
            document = await _insert_item(
                db,
                store_id,
                actor_id,
                {
                    "medicineName": item.medicineName,
                    "barcode": barcode,
                    "batchNumber": batch,
                    "expiryDate": expiry.isoformat(),
                    "quantity": int(default_quantity or 0),
                    "sellingPrice": selling_price if selling_price is not None else item.sellingPrice,
                    "reorderLevel": item.reorderLevel,
                },
            )
            created += 1
        except ApiError as exc:
            skipped.append({"barcode": barcode, "code": exc.code, "message": exc.message})
        except Exception as exc:
            logger.exception("template import row failed")
            skipped.append({"barcode": barcode, "code": "ERROR", "message": str(exc)})

    if created:
        await _audit(db, store_id, actor_id, "owner.inventory.import_template", template.id)
    return {"templateId": template.id, "created": created, "skipped": skipped}


def _parse_bill_text(text: str) -> list[dict[str, Any]]:
    """Parse supplier bill text into structured items.

    Expected format per line: MEDICINE NAME [BATCH] QTY PRICE.
    Handles OCR-dropped decimals (1250 -> 12.50).
    """
    results: list[dict[str, Any]] = []
    for raw_line in text.strip().split("\n"):
        line = raw_line.strip()
        if not line or re.match(r"^TOTAL\s+\d+\.?\d*$", line, re.IGNORECASE):
            continue
        match = re.match(r"^(.+?)\s+((?:\d+\w+\s*)+)?\s*(\d+)\s+([\d.]+)?\s*$", line)
        if not match:
            continue
        medicine_name = match.group(1).strip()
        raw_price = match.group(4)
        quantity = int(match.group(3))
        if raw_price and "." not in raw_price and len(raw_price) >= 4:
            selling_price = float(f"{raw_price[:-2]}.{raw_price[-2:]}")
        elif raw_price:
            selling_price = float(raw_price)
        else:
            selling_price = None
        results.append(
            {
                "medicineName": medicine_name,
                "quantity": quantity,
                "sellingPrice": selling_price,
            }
        )
    return results


async def scan_bill_image(db: Any, store_id: str, actor_id: str, data: bytes) -> dict[str, Any]:
    try:
        import pytesseract
        from PIL import Image
    except ImportError:
        raise ApiError(
            503, "OCR_UNAVAILABLE", "Bill OCR is not available on this server"
        ) from None

    try:
        image = Image.open(io.BytesIO(data))
        text = pytesseract.image_to_string(image)
    except Exception:
        logger.exception("bill OCR failed")
        raise ApiError(400, "OCR_FAILED", "Could not read that bill photo") from None

    items = _parse_bill_text(text)
    return {
        "rawText": text.strip(),
        "items": items,
        "suggestedBatch": "OCR-" + datetime.now(timezone.utc).strftime("%y%m%d"),
        "storeId": store_id,
        "scannedBy": actor_id,
    }
