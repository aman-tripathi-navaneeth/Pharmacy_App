"""Request and response models for the Today Dashboard & Reports module.

Money is an integer number of paise (1 rupee = 100 paise) to avoid rounding errors.
Dates and times use India Standard Time (UTC+05:30) and are returned as ISO 8601.

Storage follows the lead's universal schema conventions: store_id VARCHAR(32) NOT NULL,
UNIQUE (store_id, idempotency_key) on writes, created_at/updated_at TIMESTAMPTZ.
"""

from datetime import date, datetime
from enum import Enum
from typing import Literal

from pydantic import BaseModel, Field


class Urgency(str, Enum):
    URGENT = "urgent"
    SOON = "soon"
    ROUTINE = "routine"


class Category(str, Enum):
    CLOSE = "close"
    EXPIRY = "expiry"
    LOW_STOCK = "low_stock"
    REFILL = "refill"
    CREDIT = "credit"
    DELIVERY = "delivery"
    SYNC = "sync"


class TaskAction(BaseModel):
    type: str
    label: str
    target: str = Field(description="In-app deep link owned by the target module.")


class Task(BaseModel):
    key: str = Field(description="Stable key, for example 'expiry:batch_8812'.")
    category: Category
    urgency: Urgency
    score: float
    title: str
    detail: str
    reason: str = Field(description="Why this task is ranked where it is.")
    value_paise: int = 0
    source: str
    action: TaskAction
    state: Literal["open", "snoozed", "done"] = "open"


class Counts(BaseModel):
    urgent: int = 0
    soon: int = 0
    routine: int = 0
    snoozed: int = 0
    done_today: int = 0


class Glance(BaseModel):
    """None means the source for that figure was unavailable. It never means zero."""

    expiring_30_days_value_paise: int | None = None
    items_below_minimum: int | None = None
    credit_to_collect_paise: int | None = None


class SourceStatus(BaseModel):
    source: str
    ok: bool
    error: str | None = None


class TodayResponse(BaseModel):
    generated_at: datetime
    counts: Counts
    glance: Glance
    tasks: list[Task]
    source_status: list[SourceStatus]


class SnoozeRequest(BaseModel):
    until: date


class DailySummary(BaseModel):
    """One day's confirmed figures. None always means 'not known', never zero."""

    summary_date: date
    confirmed: bool
    note: str | None = None
    confirmed_at: datetime | None = None
    total_sales_paise: int | None = None
    total_purchases_paise: int | None = None
    udhaar_collected_paise: int | None = None
    udhaar_issued_paise: int | None = None
    expired_stock_value_paise: int | None = None
    low_stock_sku_count: int | None = None


class DailySummaryConfirmation(BaseModel):
    total_sales_paise: int = Field(ge=0)
    total_purchases_paise: int = Field(ge=0)
    udhaar_collected_paise: int = Field(ge=0)
    udhaar_issued_paise: int = Field(ge=0)
    expired_stock_value_paise: int = Field(ge=0)
    low_stock_sku_count: int = Field(ge=0)


class TrendPoint(BaseModel):
    summary_date: date
    total_sales_paise: int | None = None
    total_purchases_paise: int | None = None


class TrendResponse(BaseModel):
    points: list[TrendPoint]
    error: str | None = None


class StockNow(BaseModel):
    """Current stock health, not tied to a day. None means the owning module's tables
    are not merged yet - shown as a dash, never zero."""

    available: bool = False
    note: str | None = None
    expiring_30: int | None = None
    expiring_30_value_paise: int | None = None
    expiring_60: int | None = None
    expiring_90: int | None = None
    below_minimum: int | None = None
    out_of_stock: int | None = None


class PurchaseLine(BaseModel):
    medicine: str
    batch_no: str | None = None
    expiry_date: date | None = None
    quantity: float | None = None
    amount_paise: int | None = None


class PurchaseRegisterRow(BaseModel):
    invoice_id: str
    invoice_no: str
    invoice_date: date | None = None
    supplier: str | None = None
    total_paise: int
    item_count: int | None = None
    lines: list[PurchaseLine] | None = None


class PurchaseRegisterResponse(BaseModel):
    """Only confirmed invoices are listed. available=False is honest: the owning
    module has not been merged yet, so there is nothing to read."""

    available: bool
    note: str | None = None
    rows: list[PurchaseRegisterRow] = []
    total_paise: int | None = None
    total_count: int = 0


class TaskStateResponse(BaseModel):
    task_key: str
    status: Literal["open", "snoozed", "done"]
    snoozed_until: date | None = None
    acted_by: str | None = None
    acted_at: datetime | None = None
