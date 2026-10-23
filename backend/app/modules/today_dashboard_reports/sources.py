"""Source adapters: one per module the dashboard reads from.

NO MOCK DATA. Every adapter runs read-only SELECTs against the lead's fixed PostgreSQL
schema. If another member's module has not been merged yet, its tables do not exist,
the SELECT raises, and collect_facts marks that source unavailable - so the dashboard
shows honest empty/partial states now and renders real data the moment it lands.

Ownership note: these are reads of the shared schema from docs/data-and-stock-rules.md.
If the team later mandates per-module service functions or views, only this file
changes; facts, engine, API shapes and the frontend stay identical.
"""

from datetime import date, datetime, timedelta, timezone
from typing import Protocol

from .facts import (
    CloseFact,
    CreditFact,
    DeliveryFact,
    ExpiryFact,
    Fact,
    LowStockFact,
    RefillFact,
    SyncFact,
)

IST = timezone(timedelta(hours=5, minutes=30))  # India has no daylight saving


class TaskSource(Protocol):
    name: str

    async def fetch(self, store_id: str, now: datetime) -> list[Fact]: ...


def _today(now: datetime) -> date:
    return now.astimezone(IST).date()


def _to_paise(rupees) -> int:
    """NUMERIC rupees from the schema -> integer paise."""
    return int(round(float(rupees) * 100))


def _qty_text(qty, unit: str) -> str:
    return f"{float(qty):g} {unit}"


class _PostgresSource:
    """Shared pool handle for every real adapter."""

    def __init__(self, pool) -> None:
        self._pool = pool


class PostgresInventorySource(_PostgresSource):
    """Expiring batches and below-minimum products from batches + inventory_thresholds.

    Owners: Members 5 (Inventory, Batches & Stock Ledger) and 6 (Expiry, Low Stock).
    """

    name = "inventory"

    async def fetch(self, store_id: str, now: datetime) -> list[Fact]:
        today = _today(now)
        facts: list[Fact] = []

        # Expiring batches (window covers the engine's 90-day max urgency horizon).
        rows = await self._pool.fetch(
            """
            SELECT b.id, b.batch_number, b.expiry_date, b.current_quantity, b.base_unit,
                   b.mrp, p.name AS product_name
            FROM batches b
            JOIN products p ON p.id = b.product_id AND p.store_id = b.store_id
            WHERE b.store_id = $1
              AND b.is_active
              AND b.current_quantity > 0
              AND b.expiry_date <= $2::date + INTERVAL '90 days'
            ORDER BY b.expiry_date
            """,
            store_id,
            today,
        )
        for r in rows:
            facts.append(
                ExpiryFact(
                    key=f"expiry:{r['id']}",
                    medicine=r["product_name"],
                    batch_no=r["batch_number"],
                    quantity_text=_qty_text(r["current_quantity"], r["base_unit"]),
                    days_to_expiry=(r["expiry_date"] - today).days,
                    value_paise=_to_paise(r["mrp"] * r["current_quantity"]),
                )
            )

        # Products below their reorder point, including fully out-of-stock ones
        # (LEFT JOIN so a product with zero active batches is still counted).
        rows = await self._pool.fetch(
            """
            SELECT p.id, p.name, p.base_unit,
                   COALESCE(SUM(b.current_quantity), 0) AS qty,
                   th.reorder_point, th.safety_stock_level
            FROM products p
            JOIN inventory_thresholds th
                 ON th.product_id = p.id AND th.store_id = p.store_id
            LEFT JOIN batches b
                 ON b.product_id = p.id AND b.store_id = p.store_id AND b.is_active
            WHERE p.store_id = $1 AND p.is_active
            GROUP BY p.id, p.name, p.base_unit, th.reorder_point, th.safety_stock_level
            HAVING COALESCE(SUM(b.current_quantity), 0) < th.reorder_point
            """,
            store_id,
        )
        for r in rows:
            qty = float(r["qty"])
            facts.append(
                LowStockFact(
                    key=f"low_stock:{r['id']}",
                    medicine=r["name"],
                    out_of_stock=qty <= 0,
                    value_paise=0,
                    stock_text=_qty_text(qty, r["base_unit"]),
                    minimum_text=f"{float(r['reorder_point']):g}",
                )
            )
        return facts


class PostgresRefillSource(_PostgresSource):
    """Due refills from patient_refill_schedules; reminder failures from notification_logs.

    Owners: Members 8 (Customers, Refills & Prescriptions) and 10 (WhatsApp & Notifications).
    """

    name = "refills"

    async def fetch(self, store_id: str, now: datetime) -> list[Fact]:
        today = _today(now)
        rows = await self._pool.fetch(
            """
            SELECT prs.id, c.name AS customer, p.name AS product,
                   prs.next_refill_due_date,
                   nl.status AS last_reminder_status
            FROM patient_refill_schedules prs
            JOIN customers c ON c.id = prs.customer_id AND c.store_id = prs.store_id
            JOIN products p ON p.id = prs.product_id AND p.store_id = prs.store_id
            LEFT JOIN LATERAL (
                SELECT nl.status
                FROM notification_logs nl
                WHERE nl.customer_id = prs.customer_id
                  AND nl.store_id = prs.store_id
                  AND nl.template_name = 'REFILL_REMINDER'
                ORDER BY nl.created_at DESC
                LIMIT 1
            ) nl ON TRUE
            WHERE prs.store_id = $1
              AND prs.status = 'ACTIVE'
              AND prs.next_refill_due_date <= $2::date + INTERVAL '7 days'
            ORDER BY prs.next_refill_due_date
            """,
            store_id,
            today,
        )
        facts: list[Fact] = []
        for r in rows:
            facts.append(
                RefillFact(
                    key=f"refill:{r['id']}",
                    customer=r["customer"],
                    purpose="medicine",
                    medicine_text=r["product"],
                    days_overdue=(today - r["next_refill_due_date"]).days,
                    value_paise=0,
                    reminder_failed=r["last_reminder_status"] == "FAILED",
                )
            )
        return facts


class PostgresCreditSource(_PostgresSource):
    """Customers with an outstanding udhaar balance, from customers + customer_credit_ledger.

    Owner: Member 9 (Udhaar / Customer Credit & Payments).
    """

    name = "credit"

    async def fetch(self, store_id: str, now: datetime) -> list[Fact]:
        today = _today(now)
        rows = await self._pool.fetch(
            """
            SELECT c.id, c.name, c.outstanding_balance, c.credit_limit, c.created_at,
                   (
                       SELECT MAX(cl.created_at)
                       FROM customer_credit_ledger cl
                       WHERE cl.customer_id = c.id
                         AND cl.store_id = c.store_id
                         AND cl.entry_type = 'CREDIT_PAYMENT'
                   ) AS last_payment
            FROM customers c
            WHERE c.store_id = $1 AND c.outstanding_balance > 0
            ORDER BY c.outstanding_balance DESC
            """,
            store_id,
        )
        facts: list[Fact] = []
        for r in rows:
            last_payment = r["last_payment"] or r["created_at"]
            facts.append(
                CreditFact(
                    key=f"credit:{r['id']}",
                    customer=r["name"],
                    balance_paise=_to_paise(r["outstanding_balance"]),
                    days_since_payment=max((today - last_payment.date()).days, 0),
                    credit_limit_paise=_to_paise(r["credit_limit"]),
                )
            )
        return facts

class PostgresSupplierSource(_PostgresSource):
    """Open purchase orders that are due or late, from purchase_orders + suppliers.

    Owner: Member 3 (Suppliers & Purchase Orders).
    """

    name = "suppliers"

    async def fetch(self, store_id: str, now: datetime) -> list[Fact]:
        today = _today(now)
        rows = await self._pool.fetch(
            """
            SELECT po.id, po.po_number, s.name AS supplier, po.total_amount,
                   po.created_at, s.credit_period_days,
                   (SELECT COUNT(*) FROM purchase_order_items pi WHERE pi.po_id = po.id) AS item_count
            FROM purchase_orders po
            JOIN suppliers s ON s.id = po.supplier_id AND s.store_id = po.store_id
            WHERE po.store_id = $1 AND po.status IN ('SUBMITTED', 'PARTIAL')
            ORDER BY po.created_at
            """,
            store_id,
        )
        facts: list[Fact] = []
        for r in rows:
            expected = r["created_at"].date() + timedelta(days=r["credit_period_days"])
            facts.append(
                DeliveryFact(
                    key=f"delivery:{r['id']}",
                    order_no=r["po_number"],
                    supplier=r["supplier"],
                    days_late=(today - expected).days,
                    item_count=int(r["item_count"]),
                    value_paise=_to_paise(r["total_amount"]),
                )
            )
        return facts


class PostgresSyncSource(_PostgresSource):
    """Failed or retrying offline uploads, from sync_outbox_queue.

    Owners: Members 4 (Purchase Invoice Scanning & Inward) and 12 (Offline Sync).
    """

    name = "sync"

    async def fetch(self, store_id: str, now: datetime) -> list[Fact]:
        rows = await self._pool.fetch(
            """
            SELECT id, entity_name, entity_id, retry_count
            FROM sync_outbox_queue
            WHERE store_id = $1
              AND sync_status IN ('PENDING', 'FAILED')
              AND retry_count > 0
            ORDER BY client_timestamp
            """,
            store_id,
        )
        return [
            SyncFact(
                key=f"sync:{r['id']}",
                label=r["entity_name"].replace("_", " ").title(),
                reference=r["entity_id"],
                attempts=int(r["retry_count"]),
            )
            for r in rows
        ]


class PostgresSalesReportSource(_PostgresSource):
    """Whether today's daily summary exists, from daily_store_summaries (this module's table).

    A day counts as confirmed only when sales data exists AND the summary row was written.
    If sales_invoices does not exist yet (Member 7 not merged), to_regclass returns NULL,
    no sales are assumed, and the source answers with an empty list instead of failing.
    """

    name = "sales_reports"

    async def fetch(self, store_id: str, now: datetime) -> list[Fact]:
        today = _today(now)
        sales_table_exists = await self._pool.fetchval(
            "SELECT to_regclass('sales_invoices') IS NOT NULL"
        )
        if not sales_table_exists:
            return []
        bills_today = await self._pool.fetchval(
            """
            SELECT COUNT(*) FROM sales_invoices
            WHERE store_id = $1 AND created_at::date = $2::date
            """,
            store_id,
            today,
        )
        if not bills_today:
            return []
        confirmed = await self._pool.fetchval(
            "SELECT 1 FROM daily_store_summaries WHERE store_id = $1 AND summary_date = $2::date",
            store_id,
            today,
        )
        return [
            CloseFact(
                key="close:daily_report",
                report_confirmed_today=bool(confirmed),
                past_usual_time=now.astimezone(IST).hour >= 18,
            )
        ]


def make_default_sources(pool) -> list[TaskSource]:
    """The six real adapters, built on the backend's shared Postgres pool."""
    return [
        PostgresInventorySource(pool),
        PostgresRefillSource(pool),
        PostgresCreditSource(pool),
        PostgresSupplierSource(pool),
        PostgresSyncSource(pool),
        PostgresSalesReportSource(pool),
    ]


_SOURCE_NAMES = ("inventory", "refills", "credit", "suppliers", "sync", "sales_reports")


class _UnavailableSource:
    """Stands in when there is no database pool at all: the source reports itself
    unavailable instead of silently answering with zero tasks."""

    def __init__(self, name: str) -> None:
        self.name = name

    async def fetch(self, store_id: str, now: datetime) -> list[Fact]:
        raise RuntimeError("database not configured")


def make_unavailable_sources() -> list[TaskSource]:
    return [_UnavailableSource(name) for name in _SOURCE_NAMES]
