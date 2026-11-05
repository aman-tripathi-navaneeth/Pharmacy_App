import html
import uuid
from datetime import datetime, time, timedelta, timezone
from typing import Any

from app.core.errors import ApiError
from app.db.postgres import get_pg_connection
from app.modules.audit import service as audit
from app.modules.notifications import service as notifications


async def _resolve_customer(
    db: Any,
    store_id: str,
    actor_id: str,
    payload: dict[str, Any],
) -> dict[str, Any] | None:
    pool = await get_pg_connection(db)
    customer_id = payload.get("customerId")
    if customer_id:
        row = await pool.fetchrow(
            "SELECT * FROM customers WHERE id = $1 AND store_id = $2", customer_id, store_id
        )
        return dict(row) if row else None

    name = (payload.get("customerName") or "").strip()
    phone = (payload.get("customerPhone") or "").strip() or None
    if not name:
        return None

    if phone:
        row = await pool.fetchrow(
            "SELECT * FROM customers WHERE store_id = $1 AND phone = $2", store_id, phone
        )
        if row:
            if name and str(row["name"]) != name:
                await pool.execute(
                    "UPDATE customers SET name = $1, updated_at = $2 WHERE id = $3",
                    name,
                    datetime.now(timezone.utc),
                    row["id"],
                )
                row = await pool.fetchrow("SELECT * FROM customers WHERE id = $1", row["id"])
            return dict(row)
    else:
        row = await pool.fetchrow(
            "SELECT * FROM customers WHERE store_id = $1 AND name = $2 AND phone IS NULL",
            store_id,
            name,
        )
        if row:
            return dict(row)

    now = datetime.now(timezone.utc)
    new_id = str(uuid.uuid4())
    await pool.execute(
        """INSERT INTO customers
           (id, store_id, name, phone, balance, created_by, created_at, updated_at)
           VALUES ($1, $2, $3, $4, 0, $5, $6, $6)""",
        new_id,
        store_id,
        name,
        phone,
        actor_id or None,
        now,
    )
    return {
        "id": new_id,
        "store_id": store_id,
        "name": name,
        "phone": phone,
        "balance": 0.0,
    }


async def create_bill(
    db: Any,
    store_id: str,
    actor_id: str,
    payload: dict[str, Any],
) -> dict[str, Any]:
    customer = await _resolve_customer(db, store_id, actor_id, payload)
    now = datetime.now(timezone.utc)
    pool = await get_pg_connection(db)

    items: list[dict[str, Any]] = []
    subtotal = 0.0
    stock_deductions: list[tuple[str, int]] = []

    for raw in payload["items"]:
        inventory_id = raw.get("inventoryItemId")
        item_row: Any = None
        if inventory_id:
            item_row = await pool.fetchrow(
                "SELECT * FROM inventory_items WHERE id = $1 AND store_id = $2 AND archived = FALSE",
                inventory_id,
                store_id,
            )
            if not item_row:
                raise ApiError(400, "INVENTORY_ITEM_NOT_FOUND", "Medicine not found in inventory")
            if int(item_row["quantity"] or 0) < int(raw["quantity"]):
                raise ApiError(
                    400,
                    "INSUFFICIENT_STOCK",
                    f"Only {item_row['quantity']} left of {item_row['medicine_name']}",
                )

        medicine_name = (raw.get("medicineName") or (item_row["medicine_name"] if item_row else "") or "").strip()
        if not medicine_name:
            raise ApiError(400, "VALIDATION_ERROR", "Each bill line needs a medicine name")

        unit_price = float(raw.get("unitPrice") or 0) or float(
            (item_row["selling_price"] if item_row else 0) or 0
        )
        quantity = int(raw["quantity"])
        line_total = round(unit_price * quantity, 2)
        subtotal = round(subtotal + line_total, 2)
        items.append(
            {
                "inventoryItemId": str(item_row["id"]) if item_row else inventory_id,
                "medicineName": medicine_name,
                "batchNumber": (raw.get("batchNumber") or (item_row["batch_number"] if item_row else "") or ""),
                "quantity": quantity,
                "unitPrice": unit_price,
                "lineTotal": line_total,
            }
        )
        if item_row:
            stock_deductions.append((str(item_row["id"]), quantity))

    if not items:
        raise ApiError(400, "VALIDATION_ERROR", "A bill needs at least one line")

    discount = round(float(payload.get("discount") or 0), 2)
    tax_percent = float(payload.get("taxPercent") or 0)
    tax = round(subtotal * tax_percent / 100, 2)
    total = round(max(0.0, subtotal - discount + tax), 2)

    requested_status = payload.get("paymentStatus") or "PAID"
    paid = total if requested_status == "PAID" else float(payload.get("paidAmount") or 0)
    paid = min(round(paid, 2), total)
    due = round(total - paid, 2)
    if due <= 0:
        status = "PAID"
        due = 0.0
    elif paid > 0:
        status = "PARTIAL"
    else:
        status = "CREDIT"

    bill_id = str(uuid.uuid4())
    invoice_number = f"INV-{now:%Y%m%d}-{bill_id[:6].upper()}"
    customer_name = (customer or {}).get("name") or (payload.get("customerName") or "Walk-in customer")
    first_batch = items[0].get("batchNumber", "") if items else ""

    async with pool.acquire() as conn:
        async with conn.transaction():
            for item_id, quantity in stock_deductions:
                result = await conn.execute(
                    """UPDATE inventory_items
                       SET quantity = quantity - $1, updated_at = $2
                       WHERE id = $3 AND store_id = $4 AND quantity >= $1""",
                    quantity,
                    now,
                    item_id,
                    store_id,
                )
                if not result.endswith(" 1"):
                    raise ApiError(
                        400, "INSUFFICIENT_STOCK", "Stock changed while billing. Try again."
                    )

            await conn.execute(
                """INSERT INTO bills
                   (id, store_id, invoice_number, customer_id, customer_name, customer_phone,
                    items, subtotal, discount, tax_percent, tax, total, paid_amount, due_amount,
                    payment_status, payment_method, notes, batch_number, created_by,
                    created_at, updated_at)
                   VALUES ($1, $2, $3, $4, $5, $6, $7::jsonb, $8, $9, $10, $11, $12,
                           $13, $14, $15, $16, $17, $18, $19, $20, $20)""",
                bill_id,
                store_id,
                invoice_number,
                str(customer["id"]) if customer else None,
                customer_name,
                (customer or {}).get("phone") or payload.get("customerPhone"),
                items,
                subtotal,
                discount,
                tax_percent,
                tax,
                total,
                paid,
                due,
                status,
                payload.get("paymentMethod") or "CASH",
                payload.get("notes"),
                first_batch,
                actor_id or None,
                now,
            )

            if customer and due > 0:
                await conn.execute(
                    "UPDATE customers SET balance = balance + $1, updated_at = $2 WHERE id = $3",
                    due,
                    now,
                    str(customer["id"]),
                )

    document = {
        "id": bill_id,
        "store_id": store_id,
        "invoice_number": invoice_number,
        "customer_id": str(customer["id"]) if customer else None,
        "customer_name": customer_name,
        "customer_phone": (customer or {}).get("phone") or payload.get("customerPhone"),
        "items": items,
        "subtotal": subtotal,
        "discount": discount,
        "tax_percent": tax_percent,
        "tax": tax,
        "total": total,
        "paid_amount": paid,
        "due_amount": due,
        "payment_status": status,
        "payment_method": payload.get("paymentMethod") or "CASH",
        "notes": payload.get("notes"),
        "batch_number": first_batch,
        "created_by": actor_id,
        "created_at": now,
        "updated_at": now,
    }

    await notifications.notify(
        db,
        user_id=actor_id,
        store_id=store_id,
        title="Bill created",
        message=f"{invoice_number} · ₹{total:.2f} · {customer_name}",
        type_="BILL",
    )
    if customer and due > 0:
        await notifications.notify(
            db,
            user_id=actor_id,
            store_id=store_id,
            title="Udhaar updated",
            message=f"₹{due:.2f} added to {customer_name}'s credit balance.",
            type_="UDHAAR",
        )

    for item_id, _quantity in stock_deductions:
        item_doc = await pool.fetchrow("SELECT * FROM inventory_items WHERE id = $1", item_id)
        if item_doc and int(item_doc["quantity"] or 0) <= int(item_doc["reorder_level"] or 0):
            await notifications.notify(
                db,
                user_id=actor_id,
                store_id=store_id,
                title="Low stock alert",
                message=(
                    f"{item_doc['medicine_name']} is running low "
                    f"({item_doc['quantity']} left, reorder at {item_doc['reorder_level']})."
                ),
                type_="INVENTORY",
            )

    await audit.record(
        db,
        actor_user_id=actor_id,
        actor_role="SHOP_OWNER",
        store_id=store_id,
        action="owner.bill.create",
        target_type="bill",
        target_id=bill_id,
        result="SUCCESS",
    )
    return document


async def list_bills(
    db: Any,
    store_id: str,
    *,
    customer_id: str | None = None,
    date: str | None = None,
    limit: int = 100,
) -> list[dict[str, Any]]:
    pool = await get_pg_connection(db)
    query = "SELECT * FROM bills WHERE store_id = $1"
    args: list[Any] = [store_id]
    if customer_id:
        args.append(customer_id)
        query += " AND customer_id = $" + str(len(args))
    if date:
        try:
            start = datetime.strptime(date, "%Y-%m-%d").replace(tzinfo=timezone.utc)
        except ValueError:
            raise ApiError(400, "VALIDATION_ERROR", "Use date format YYYY-MM-DD") from None
        args.extend([start, start + timedelta(days=1)])
        query += " AND created_at >= $" + str(len(args) - 1) + " AND created_at < $" + str(len(args))
    args.append(limit)
    query += " ORDER BY created_at DESC LIMIT $" + str(len(args))
    rows = await pool.fetch(query, *args)
    return [dict(row) for row in rows]


async def find_bill(db: Any, store_id: str, bill_id: str) -> dict[str, Any]:
    pool = await get_pg_connection(db)
    row = await pool.fetchrow(
        "SELECT * FROM bills WHERE id = $1 AND store_id = $2", bill_id, store_id
    )
    if row:
        return dict(row)
    raise ApiError(404, "BILL_NOT_FOUND", "Bill not found")


def _day_range(date_value: str) -> tuple[datetime, datetime]:
    try:
        day = datetime.strptime(date_value, "%Y-%m-%d").date()
    except ValueError:
        raise ApiError(400, "VALIDATION_ERROR", "Use date format YYYY-MM-DD") from None
    start = datetime.combine(day, time.min, tzinfo=timezone.utc)
    return start, start + timedelta(days=1)


async def invoice_html(db: Any, store_id: str, bill_id: str) -> str:
    bill = await find_bill(db, store_id, bill_id)
    pool = await get_pg_connection(db)
    shop_row = await pool.fetchrow("SELECT * FROM shops WHERE id = $1", store_id)
    shop = dict(shop_row) if shop_row else {}
    address = shop.get("address") or {}
    payment_settings = shop.get("payment_settings") or {}
    upi_id = payment_settings.get("upiId") or ""
    payment_method = bill.get("payment_method") or "CASH"
    payment_line = (
        "Cash" if payment_method == "CASH" else f"Online (UPI: {html.escape(upi_id) or 'not configured'})"
    )
    address_line = ", ".join(
        part
        for part in [
            address.get("line1"),
            address.get("line2"),
            address.get("city"),
            address.get("state"),
            address.get("postalCode"),
        ]
        if part
    )

    rows = "".join(
        f"<tr><td>{html.escape(str(item['medicineName']))}</td>"
        f"<td>{html.escape(str(item.get('batchNumber') or '-'))}</td>"
        f"<td class='r'>{item['quantity']}</td>"
        f"<td class='r'>₹{item['unitPrice']:.2f}</td>"
        f"<td class='r'>₹{item['lineTotal']:.2f}</td></tr>"
        for item in bill["items"]
    )
    return f"""<!doctype html>
<html><head><meta charset="utf-8"><title>{html.escape(bill['invoice_number'])}</title>
<style>
body{{font-family:system-ui,Segoe UI,sans-serif;background:#f6f8f7;margin:0;padding:24px;color:#132f29}}
.sheet{{max-width:720px;margin:0 auto;background:#fff;border:1px solid #dfe7e4;border-radius:12px;padding:28px}}
h1{{font-size:20px;margin:0 0 4px}} .muted{{color:#5d6f6a;font-size:13px}}
.head{{display:flex;justify-content:space-between;gap:20px;border-bottom:2px solid #0e6b5c;padding-bottom:14px;margin-bottom:18px}}
table{{width:100%;border-collapse:collapse;margin-top:14px;font-size:14px}}
th,td{{text-align:left;padding:8px;border-bottom:1px solid #e6ecea}} th{{font-size:12px;text-transform:uppercase;letter-spacing:.06em;color:#5d6f6a}}
.r{{text-align:right}} .totals{{margin-top:16px;margin-left:auto;width:280px}}
.totals div{{display:flex;justify-content:space-between;padding:4px 0}}
.totals .grand{{border-top:2px solid #132f29;margin-top:6px;padding-top:8px;font-weight:700;font-size:16px}}
.badge{{display:inline-block;padding:3px 9px;border-radius:20px;font-size:12px;font-weight:700;background:#e3f1ee;color:#0e6b5c}}
.footer{{margin-top:22px;font-size:12px;color:#5d6f6a;border-top:1px solid #e6ecea;padding-top:10px}}
@media print{{body{{background:#fff;padding:0}} .sheet{{border:none;border-radius:0}}}}
</style></head><body><div class="sheet">
<div class="head"><div><h1>{html.escape(str(shop.get('shop_name') or 'Pharmacy'))}</h1>
<div class="muted">{html.escape(address_line)}</div>
<div class="muted">{html.escape(str(shop.get('phone_e164') or ''))}</div></div>
<div class="r"><div class="muted">Invoice</div><h1>{html.escape(bill['invoice_number'])}</h1>
<div class="muted">{bill['created_at'].strftime('%d %b %Y, %H:%M')}</div>
<span class="badge">{bill['payment_status']}</span></div></div>
<div><strong>Bill to</strong><div>{html.escape(str(bill['customer_name'] or 'Walk-in customer'))}</div>
<div class="muted">{html.escape(str(bill['customer_phone'] or ''))}</div></div>
<table><thead><tr><th>Medicine</th><th>Batch</th><th class="r">Qty</th><th class="r">Rate</th><th class="r">Amount</th></tr></thead>
<tbody>{rows}</tbody></table>
<div class="totals"><div><span>Subtotal</span><span>₹{bill['subtotal']:.2f}</span></div>
<div><span>Discount</span><span>−₹{bill['discount']:.2f}</span></div>
<div><span>Tax ({bill['tax_percent']:g}%)</span><span>₹{bill['tax']:.2f}</span></div>
<div class="grand"><span>Total</span><span>₹{bill['total']:.2f}</span></div>
<div><span>Paid</span><span>₹{bill['paid_amount']:.2f}</span></div>
<div><span>Due</span><span>₹{bill['due_amount']:.2f}</span></div>
<div><span>Payment mode</span><span>{payment_line}</span></div></div>
<div class="footer">Thank you. Keep this invoice for returns and warranty. Generated by MediManage.</div>
</div></body></html>"""
