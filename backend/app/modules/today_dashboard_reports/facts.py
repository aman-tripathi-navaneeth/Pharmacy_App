"""Plain facts that source modules report to the dashboard.

Each source adapter returns these. The task engine turns facts into ranked tasks.
The dashboard never reads other modules' collections; adapters call their services.
"""

from dataclasses import dataclass, field
from datetime import date


@dataclass(frozen=True)
class ExpiryFact:
    key: str
    medicine: str
    batch_no: str
    quantity_text: str
    days_to_expiry: int
    value_paise: int
    return_days_left: int | None = None  # days until the supplier's return window closes
    supplier: str | None = None


@dataclass(frozen=True)
class LowStockFact:
    key: str
    medicine: str
    out_of_stock: bool
    value_paise: int
    stock_text: str = ""
    minimum_text: str = ""
    days_of_cover: float | None = None
    last_supplier: str | None = None
    sold_last_week_text: str | None = None


@dataclass(frozen=True)
class RefillFact:
    key: str
    customer: str
    purpose: str  # for example "BP" or "sugar"
    medicine_text: str
    days_overdue: int  # negative means due in the future
    value_paise: int = 0
    reminder_failed: bool = False


@dataclass(frozen=True)
class CreditFact:
    key: str
    customer: str
    balance_paise: int
    days_since_payment: int
    credit_limit_paise: int | None = None


@dataclass(frozen=True)
class DeliveryFact:
    key: str
    order_no: str
    supplier: str
    days_late: int  # 0 means arriving today, negative means not due yet
    item_count: int
    value_paise: int


@dataclass(frozen=True)
class SyncFact:
    key: str
    label: str  # for example "Invoice photo"
    reference: str
    attempts: int
    supplier: str | None = None
    value_paise: int = 0


@dataclass(frozen=True)
class CloseFact:
    key: str
    report_confirmed_today: bool
    past_usual_time: bool
    missed_dates: tuple[date, ...] = field(default_factory=tuple)


Fact = ExpiryFact | LowStockFact | RefillFact | CreditFact | DeliveryFact | SyncFact | CloseFact
