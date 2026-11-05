"""Summary-tab and Purchases-tab report reads.

Read-only views for the daily summary (design frames 08/09) and the purchase
register (frames 10/11). Every read follows the module boundary:

* This module's figures come from daily_store_summaries (owned by this module,
  see migration 0002).
* Purchase invoices belong to Members 3/4. Until their tables are merged, to_regclass
  returns NULL and we report available=False — an honest 'nothing to read yet', never
  demo data, and never zero presented as a real total.
"""

from datetime import date, datetime, timedelta, timezone

from asyncpg import Pool

from .schemas import (
    DailySummary,
    PurchaseLine,
    PurchaseRegisterResponse,
    PurchaseRegisterRow,
    StockNow,
    TrendPoint,
    TrendResponse,
)

IST = timezone(timedelta(hours=5, minutes=30))  # India has no daylight saving
WEEK_DAYS = 7


class SummaryConflictError(Exception):
    """Raised when a confirmed daily summary is submitted again with different values."""


def _to_paise(rupees) -> int | None:
    if rupees is None:
        return None
    return int(round(float(rupees) * 100))


async def daily_summary(pool: Pool, store_id: str, day: date) -> DailySummary:
    row = await pool.fetchrow(
        """
        SELECT summary_date, total_sales_amount, total_purchases_amount,
               udhaar_collected_amount, udhaar_issued_amount,
               expired_stock_value, low_stock_sku_count, created_at
        FROM daily_store_summaries
        WHERE store_id = $1 AND summary_date = $2::date
        """,
        store_id,
        day,
    )
    if row is None:
        # Design frame 09: a missing report is 'waiting', never zero.
        return DailySummary(
            summary_date=day,
            confirmed=False,
            note="Today's sales report is not confirmed yet, so sales and "
            "profit show after you scan it.",
        )
    return DailySummary(
        summary_date=row["summary_date"],
        confirmed=True,
        note=None,
        confirmed_at=row["created_at"],
        total_sales_paise=_to_paise(row["total_sales_amount"]),
        total_purchases_paise=_to_paise(row["total_purchases_amount"]),
        udhaar_collected_paise=_to_paise(row["udhaar_collected_amount"]),
        udhaar_issued_paise=_to_paise(row["udhaar_issued_amount"]),
        expired_stock_value_paise=_to_paise(row["expired_stock_value"]),
        low_stock_sku_count=row["low_stock_sku_count"],
    )


async def trend(pool: Pool, store_id: str, today: date) -> TrendResponse:
    rows = await pool.fetch(
        """
        SELECT summary_date, total_sales_amount, total_purchases_amount
        FROM daily_store_summaries
        WHERE store_id = $1
          AND summary_date BETWEEN $2::date - $3::int AND $2::date
        """,
        store_id,
        today,
        WEEK_DAYS - 1,
    )
    by_date = {r["summary_date"]: r for r in rows}
    points: list[TrendPoint] = []
    for offset in range(WEEK_DAYS - 1, -1, -1):
        day = today - timedelta(days=offset)
        r = by_date.get(day)
        # A day with no confirmed row is shown as a missing bar, never zero.
        points.append(
            TrendPoint(
                summary_date=day,
                total_sales_paise=_to_paise(r["total_sales_amount"]) if r else None,
                total_purchases_paise=_to_paise(r["total_purchases_amount"]) if r else None,
            )
        )
    return TrendResponse(points=points)


async def stock_now(pool: Pool, store_id: str, today: date) -> StockNow:
    """Current stock health from batches + inventory_thresholds (Members 5/6's tables).

    Returns available=False when their tables are not merged yet, so the frontend
    shows dashes instead of false zeros.
    """
    has_tables = await pool.fetchval(
        """
        SELECT CASE WHEN to_regclass('batches') IS NOT NULL
                     AND to_regclass('inventory_thresholds') IS NOT NULL
                    THEN 1 ELSE 0 END
        """
    )
    if not has_tables:
        return StockNow(available=False, note="Inventory module has not been merged yet.")

    expiring_30 = await pool.fetch(
        """
        SELECT COUNT(*) AS n, COALESCE(SUM(b.mrp * b.current_quantity), 0) AS value
        FROM batches b
        WHERE b.store_id = $1
          AND b.is_active
          AND b.current_quantity > 0
          AND b.expiry_date BETWEEN $2::date AND $2::date + INTERVAL '30 days'
        """,
        store_id,
        today,
    )
    expiring_60 = await pool.fetchval(
        """
        SELECT COUNT(*) FROM batches b
        WHERE b.store_id = $1
          AND b.is_active
          AND b.current_quantity > 0
          AND b.expiry_date BETWEEN $2::date + INTERVAL '31 days'
                                AND $2::date + INTERVAL '60 days'
        """,
        store_id,
        today,
    )
    expiring_90 = await pool.fetchval(
        """
        SELECT COUNT(*) FROM batches b
        WHERE b.store_id = $1
          AND b.is_active
          AND b.current_quantity > 0
          AND b.expiry_date BETWEEN $2::date + INTERVAL '61 days'
                                AND $2::date + INTERVAL '90 days'
        """,
        store_id,
        today,
    )
    low = await pool.fetch(
        """
        SELECT COUNT(*) AS n,
               COUNT(*) FILTER (
                   WHERE COALESCE(current_quantity, 0) = 0
               ) AS out_of_stock
        FROM (
            SELECT COALESCE(SUM(b.current_quantity), 0) AS current_quantity
            FROM products p
            JOIN inventory_thresholds th
                 ON th.product_id = p.id AND th.store_id = p.store_id
            LEFT JOIN batches b
                 ON b.product_id = p.id AND b.store_id = p.store_id AND b.is_active
            WHERE p.store_id = $1
            GROUP BY p.id, th.reorder_point
            HAVING COALESCE(SUM(b.current_quantity), 0) < th.reorder_point
        ) items
        """,
        store_id,
    )
    row30 = expiring_30[0]
    return StockNow(
        available=True,
        expiring_30=row30["n"],
        expiring_30_value_paise=_to_paise(row30["value"]),
        expiring_60=expiring_60,
        expiring_90=expiring_90,
        below_minimum=low[0]["n"],
        out_of_stock=low[0]["out_of_stock"],
    )


async def write_daily_summary(
    pool: Pool, store_id: str, day: date,
    total_sales_paise: int | None, total_purchases_paise: int | None,
    udhaar_collected_paise: int | None, udhaar_issued_paise: int | None,
    expired_stock_value_paise: int | None, low_stock_sku_count: int | None
) -> DailySummary:
    """Write a confirmed daily summary once into daily_store_summaries.

    Repeating the same confirmation is idempotent. A different confirmation for an
    already-confirmed day is rejected rather than silently overwriting the report.
    All amounts are integer paise (1 rupee = 100 paise). We convert to rupees
    for storage since the DB columns are NUMERIC(12,2) rupees.
    """
    # Convert paise → rupees for DB storage (columns are NUMERIC(12,2) rupees)
    total_sales_rupees = total_sales_paise / 100 if total_sales_paise is not None else None
    total_purchases_rupees = total_purchases_paise / 100 if total_purchases_paise is not None else None
    udhaar_collected_rupees = udhaar_collected_paise / 100 if udhaar_collected_paise is not None else None
    udhaar_issued_rupees = udhaar_issued_paise / 100 if udhaar_issued_paise is not None else None
    expired_stock_value_rupees = expired_stock_value_paise / 100 if expired_stock_value_paise is not None else None

    await pool.execute(
        """
        INSERT INTO daily_store_summaries
        (store_id, summary_date, total_sales_amount, total_purchases_amount,
         udhaar_collected_amount, udhaar_issued_amount, expired_stock_value,
         low_stock_sku_count, idempotency_key, created_at, updated_at)
        VALUES ($1, $2::date, $3, $4, $5, $6, $7, $8, gen_random_uuid(), now(), now())
        ON CONFLICT (store_id, summary_date) DO NOTHING
        """,
        store_id, day, total_sales_rupees, total_purchases_rupees,
        udhaar_collected_rupees, udhaar_issued_rupees, expired_stock_value_rupees, low_stock_sku_count,
    )
    summary = await daily_summary(pool, store_id, day)
    submitted = (
        total_sales_paise,
        total_purchases_paise,
        udhaar_collected_paise,
        udhaar_issued_paise,
        expired_stock_value_paise,
        low_stock_sku_count,
    )
    saved = (
        summary.total_sales_paise,
        summary.total_purchases_paise,
        summary.udhaar_collected_paise,
        summary.udhaar_issued_paise,
        summary.expired_stock_value_paise,
        summary.low_stock_sku_count,
    )
    if submitted != saved:
        raise SummaryConflictError("A different summary has already been confirmed for this date.")
    return summary


async def purchase_register(
    pool: Pool, store_id: str, query: str | None, *, limit: int = 50, offset: int = 0
) -> PurchaseRegisterResponse:
    """Confirmed supplier invoices, read from purchase_invoices (Members 3/4's table).

    The register lists only confirmed invoices — drafts never appear here.
    """
    has_table = await pool.fetchval("SELECT CASE WHEN to_regclass('purchase_invoices') IS NOT NULL THEN 1 ELSE 0 END")
    if not has_table:
        return PurchaseRegisterResponse(
            available=False,
            note="The purchase module has not been merged yet, so there are no invoices to show.",
        )

    pattern = f"%{query}%"
    total_count = await pool.fetchval(
        """
        SELECT COUNT(*)
        FROM purchase_invoices pi
        LEFT JOIN suppliers s ON s.id = pi.supplier_id AND s.store_id = pi.store_id
        WHERE pi.store_id = $1
          AND pi.status = 'CONFIRMED'
          AND ($2::text = '' OR pi.invoice_no ILIKE $3 OR s.name ILIKE $3)
        """,
        store_id,
        query or "",
        pattern,
    )
    rows = await pool.fetch(
        """
        SELECT pi.id, pi.invoice_no, pi.invoice_date, s.name AS supplier,
               pi.total_amount,
               (SELECT COUNT(*) FROM purchase_invoice_items pl
                WHERE pl.invoice_id = pi.id) AS item_count
        FROM purchase_invoices pi
        LEFT JOIN suppliers s ON s.id = pi.supplier_id AND s.store_id = pi.store_id
        WHERE pi.store_id = $1
          AND pi.status = 'CONFIRMED'
          AND ($2::text = '' OR pi.invoice_no ILIKE $3 OR s.name ILIKE $3)
        ORDER BY pi.invoice_date DESC NULLS LAST, pi.id DESC
        LIMIT $4 OFFSET $5
        """,
        store_id,
        query or "",
        pattern,
        limit,
        offset,
    )
    if not rows:
        return PurchaseRegisterResponse(
            available=True, rows=[], total_paise=0, total_count=total_count
        )

    invoice_ids = [r["id"] for r in rows]
    line_rows = await pool.fetch(
        """
        SELECT pl.invoice_id, p.name AS medicine, pl.batch_number, pl.expiry_date,
               pl.quantity, pl.line_amount
        FROM purchase_invoice_items pl
        JOIN purchase_invoices pi ON pi.id = pl.invoice_id AND pi.store_id = $2
        JOIN products p ON p.id = pl.product_id AND p.store_id = pi.store_id
        WHERE pl.invoice_id = ANY($1)
        """,
        invoice_ids,
        store_id,
    )
    lines_by_invoice: dict[str, list[PurchaseLine]] = {}
    for lr in line_rows:
        lines_by_invoice.setdefault(lr["invoice_id"], []).append(
            PurchaseLine(
                medicine=lr["medicine"],
                batch_no=lr["batch_number"],
                expiry_date=lr["expiry_date"],
                quantity=float(lr["quantity"]) if lr["quantity"] is not None else None,
                amount_paise=_to_paise(lr["line_amount"]),
            )
        )
    rows_out: list[PurchaseRegisterRow] = [
        PurchaseRegisterRow(
            invoice_id=str(r["id"]),
            invoice_no=r["invoice_no"],
            invoice_date=r["invoice_date"],
            supplier=r["supplier"],
            total_paise=_to_paise(r["total_amount"]),
            item_count=r["item_count"],
            lines=lines_by_invoice.get(str(r["id"])),
        )
        for r in rows
    ]
    total = sum(r.total_paise for r in rows_out)
    return PurchaseRegisterResponse(
        available=True, rows=rows_out, total_paise=total, total_count=total_count
    )