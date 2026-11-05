from datetime import datetime, time, timedelta, timezone
from typing import Any

from app.core.errors import ApiError
from app.db.postgres import get_pg_connection


def _day_range(date_value: str | None) -> tuple[datetime, datetime, str]:
    if date_value:
        try:
            day = datetime.strptime(date_value, "%Y-%m-%d").date()
        except ValueError:
            raise ApiError(400, "VALIDATION_ERROR", "Use date format YYYY-MM-DD") from None
    else:
        day = datetime.now(timezone.utc).date()
    start = datetime.combine(day, time.min, tzinfo=timezone.utc)
    return start, start + timedelta(days=1), day.isoformat()


async def overview(db: Any, store_id: str, date_value: str | None = None) -> dict[str, Any]:
    start, end, day_label = _day_range(date_value)
    pool = await get_pg_connection(db)

    async with pool.acquire() as conn:
        sales_row = await conn.fetchrow(
            """SELECT
                 COUNT(*) AS bills,
                 COALESCE(SUM(total), 0) AS revenue,
                 COALESCE(SUM(paid_amount), 0) AS paid,
                 COALESCE(SUM(due_amount), 0) AS due
               FROM bills
               WHERE store_id = $1 AND created_at >= $2 AND created_at < $3""",
            store_id,
            start,
            end,
        )
        top_rows = await conn.fetch(
            """SELECT item->>'medicineName' AS medicine_name,
                      SUM((item->>'quantity')::int) AS quantity,
                      SUM((item->>'lineTotal')::float) AS revenue
               FROM bills, LATERAL jsonb_array_elements(items) AS item
               WHERE store_id = $1 AND created_at >= $2 AND created_at < $3
               GROUP BY 1
               ORDER BY quantity DESC
               LIMIT 8""",
            store_id,
            start,
            end,
        )
        inventory_row = await conn.fetchrow(
            """SELECT
                 COUNT(*) AS items,
                 COUNT(*) FILTER (WHERE quantity <= reorder_level) AS low_stock,
                 COUNT(*) FILTER (
                   WHERE expiry_date IS NOT NULL
                     AND expiry_date < NOW() + INTERVAL '30 days'
                 ) AS expiring_30,
                 COUNT(*) FILTER (
                   WHERE expiry_date IS NOT NULL
                     AND expiry_date < NOW() + INTERVAL '90 days'
                 ) AS expiring_90,
                 COALESCE(SUM(quantity * selling_price), 0) AS stock_value
               FROM inventory_items
               WHERE store_id = $1 AND archived = FALSE""",
            store_id,
        )
        customers_row = await conn.fetchrow(
            """SELECT
                 COUNT(*) AS total,
                 COALESCE(SUM(balance) FILTER (WHERE balance > 0), 0) AS outstanding,
                 COUNT(*) FILTER (WHERE balance > 0) AS with_dues
               FROM customers WHERE store_id = $1""",
            store_id,
        )
        trend_rows = await conn.fetch(
            """SELECT date_trunc('day', created_at AT TIME ZONE 'UTC') AS day,
                      COALESCE(SUM(total), 0) AS revenue,
                      COUNT(*) AS bills
               FROM bills
               WHERE store_id = $1 AND created_at >= $2 AND created_at < $3
               GROUP BY 1 ORDER BY 1""",
            store_id,
            end - timedelta(days=7),
            end,
        )

    buckets: dict[str, dict[str, Any]] = {}
    for offset in range(7):
        bucket_day = (start - timedelta(days=6 - offset)).date().isoformat()
        buckets[bucket_day] = {"date": bucket_day, "revenue": 0.0, "bills": 0}
    for row in trend_rows:
        key = row["day"].date().isoformat()
        if key in buckets:
            buckets[key]["revenue"] = round(float(row["revenue"]), 2)
            buckets[key]["bills"] = int(row["bills"])

    bill_count = int(sales_row["bills"]) if sales_row else 0
    revenue = float(sales_row["revenue"]) if sales_row else 0.0

    return {
        "date": day_label,
        "sales": {
            "bills": bill_count,
            "revenue": round(revenue, 2),
            "paid": round(float(sales_row["paid"]), 2) if sales_row else 0.0,
            "due": round(float(sales_row["due"]), 2) if sales_row else 0.0,
            "averageBill": round(revenue / bill_count, 2) if bill_count else 0,
        },
        "topMedicines": [
            {
                "medicineName": row["medicine_name"] or "Unknown",
                "quantity": int(row["quantity"] or 0),
                "revenue": round(float(row["revenue"] or 0), 2),
            }
            for row in top_rows
        ],
        "inventory": {
            "items": int(inventory_row["items"]) if inventory_row else 0,
            "lowStock": int(inventory_row["low_stock"]) if inventory_row else 0,
            "expiring30": int(inventory_row["expiring_30"]) if inventory_row else 0,
            "expiring90": int(inventory_row["expiring_90"]) if inventory_row else 0,
            "stockValue": round(float(inventory_row["stock_value"]), 2) if inventory_row else 0.0,
        },
        "customers": {
            "total": int(customers_row["total"]) if customers_row else 0,
            "outstanding": round(float(customers_row["outstanding"]), 2) if customers_row else 0.0,
            "withDues": int(customers_row["with_dues"]) if customers_row else 0,
        },
        "last7Days": [buckets[key] for key in sorted(buckets)],
    }
