"""Task engine: turns facts into ranked tasks. Pure functions, no database, no network.

Rules and thresholds mirror section 5 of the module guide. Keep them here, in one place,
so they are easy to test and to change.
"""

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
from .schemas import Category, Task, TaskAction, Urgency

BASE_SCORE = {Urgency.URGENT: 100, Urgency.SOON: 60, Urgency.ROUTINE: 30}

SOURCE_LABELS = {
    Category.CLOSE: "Sales report scan",
    Category.EXPIRY: "Expiry and low stock",
    Category.LOW_STOCK: "Expiry and low stock",
    Category.REFILL: "Customers and refills",
    Category.CREDIT: "Udhaar and payments",
    Category.DELIVERY: "Suppliers and orders",
    Category.SYNC: "Offline sync",
}


# ---------- small helpers ----------
def indian_group(n: int) -> str:
    """12345678 -> '1,23,45,678'."""
    s = str(abs(n))
    if len(s) > 3:
        head, tail = s[:-3], s[-3:]
        parts = []
        while len(head) > 2:
            parts.insert(0, head[-2:])
            head = head[:-2]
        if head:
            parts.insert(0, head)
        s = ",".join(parts) + "," + tail
    return ("-" if n < 0 else "") + s


def format_rupees(paise: int) -> str:
    rupees, rem = divmod(abs(paise), 100)
    text = indian_group(rupees)
    if rem:
        text += f".{rem:02d}"
    return ("-" if paise < 0 else "") + "\u20b9" + text


def _days(n: int) -> str:
    return f"{n} day" if n == 1 else f"{n} days"


def compute_score(urgency: Urgency, days_overdue: int, value_paise: int) -> float:
    """base(urgency) + 3 x min(days overdue, 20) + min(rupees at risk / 500, 20)."""
    overdue_points = 3 * min(max(days_overdue, 0), 20)
    value_points = min(max(value_paise, 0) / 100 / 500, 20)
    return round(BASE_SCORE[urgency] + overdue_points + value_points, 1)


def _task(
    fact: Fact,
    category: Category,
    urgency: Urgency,
    title: str,
    detail: str,
    reason: str,
    action: TaskAction,
    value_paise: int = 0,
    days_overdue: int = 0,
) -> Task:
    return Task(
        key=fact.key,
        category=category,
        urgency=urgency,
        score=compute_score(urgency, days_overdue, value_paise),
        title=title,
        detail=detail,
        reason=reason,
        value_paise=value_paise,
        source=SOURCE_LABELS[category],
        action=action,
    )


# ---------- one rule function per category ----------
def _expiry(f: ExpiryFact) -> Task | None:
    d, rw = f.days_to_expiry, f.return_days_left
    window_closing = rw is not None and 0 <= rw <= 14
    if d <= 30 or window_closing:
        urgency = Urgency.URGENT
    elif d <= 60:
        urgency = Urgency.SOON
    elif d <= 90:
        urgency = Urgency.ROUTINE
    else:
        return None

    title = f"{f.medicine} has expired" if d <= 0 else f"{f.medicine} expires in {_days(d)}"
    detail = f"Batch {f.batch_no}, {f.quantity_text}."
    if rw is not None and rw < 0:
        detail += " The supplier return window has closed."
    elif rw is not None and f.supplier:
        detail += f" {f.supplier} takes returns for {_days(rw)} more."

    if rw is not None and rw < 0:
        reason = "Return window closed"
    elif window_closing:
        reason = f"Return window closes in {_days(rw)}"
    else:
        reason = "Expired" if d <= 0 else f"{_days(d)} left"

    if window_closing and urgency is Urgency.URGENT:
        action = TaskAction(type="plan_return", label="Plan return", target=f"app://returns/new?task={f.key}")
    else:
        action = TaskAction(type="view_batch", label="View batch", target=f"app://inventory/batches?task={f.key}")
    return _task(f, Category.EXPIRY, urgency, title, detail, reason, action, f.value_paise)


def _low_stock(f: LowStockFact) -> Task | None:
    reorder = TaskAction(type="reorder", label="Reorder", target=f"app://orders/new?task={f.key}")
    if f.out_of_stock:
        bits = []
        if f.sold_last_week_text:
            bits.append(f"Sold {f.sold_last_week_text} last week.")
        if f.last_supplier:
            bits.append(f"Last bought from {f.last_supplier}.")
        return _task(f, Category.LOW_STOCK, Urgency.URGENT, f"{f.medicine} is out of stock",
                     " ".join(bits) or "No stock on the shelf.", "Out of stock", reorder, f.value_paise)
    soon = f.days_of_cover is not None and f.days_of_cover <= 3
    detail = " ".join(x for x in (f"{f.stock_text} left, minimum {f.minimum_text}." if f.stock_text else "",) if x)
    reason = f"Out in about {_days(max(1, round(f.days_of_cover)))}" if soon else "Below minimum"
    return _task(f, Category.LOW_STOCK, Urgency.SOON if soon else Urgency.ROUTINE,
                 f"{f.medicine} is below minimum", detail or "Below the reorder level.", reason, reorder, f.value_paise)


def _refill(f: RefillFact) -> Task | None:
    n = f.days_overdue
    if n >= 7:
        urgency = Urgency.URGENT
    elif n >= 0:
        urgency = Urgency.SOON
    elif n >= -3:
        urgency = Urgency.ROUTINE
    else:
        return None
    if n > 0:
        title = f"{f.customer}\u2019s {f.purpose} refill is {_days(n)} overdue"
        reason = f"{_days(n)} overdue"
    elif n == 0:
        title = f"{f.customer}\u2019s {f.purpose} refill is due today"
        reason = "Due today"
    else:
        title = f"{f.customer}\u2019s {f.purpose} refill is due in {_days(-n)}"
        reason = f"Due in {_days(-n)}"
    detail = f"{f.medicine_text}." + (" The WhatsApp reminder failed." if f.reminder_failed else "")
    label = "Resend reminder" if f.reminder_failed else "Send reminder"
    action = TaskAction(type="send_reminder", label=label, target=f"app://refills/remind?task={f.key}")
    return _task(f, Category.REFILL, urgency, title, detail, reason, action, f.value_paise, max(n, 0))


def _credit(f: CreditFact) -> Task | None:
    over_limit = f.credit_limit_paise is not None and f.balance_paise > f.credit_limit_paise
    if over_limit or f.days_since_payment > 30:
        urgency = Urgency.URGENT
    elif f.days_since_payment > 7:
        urgency = Urgency.ROUTINE
    else:
        return None
    detail = f"No payment for {_days(f.days_since_payment)}."
    if over_limit:
        detail += f" Over the {format_rupees(f.credit_limit_paise)} credit limit."
    action = TaskAction(type="send_reminder", label="Send reminder", target=f"app://credit/remind?task={f.key}")
    return _task(f, Category.CREDIT, urgency, f"{f.customer} owes {format_rupees(f.balance_paise)}", detail,
                 f"{_days(f.days_since_payment)} since last payment", action, f.balance_paise, f.days_since_payment)


def _delivery(f: DeliveryFact) -> Task | None:
    n = f.days_late
    if n > 3:
        urgency = Urgency.URGENT
    elif n >= 1:
        urgency = Urgency.SOON
    elif n == 0:
        urgency = Urgency.ROUTINE
    else:
        return None
    detail = f"{f.supplier}, {f.item_count} items worth {format_rupees(f.value_paise)}."
    if n == 0:
        title, reason = f"Order {f.order_no} arrives today", "Arrives today"
        detail += " Scan the invoice when it arrives."
    else:
        title, reason = f"Order {f.order_no} is {_days(n)} late", f"{_days(n)} late"
    action = TaskAction(type="track_order", label="Track order", target=f"app://orders/{f.order_no}")
    return _task(f, Category.DELIVERY, urgency, title, detail, reason, action, f.value_paise, max(n, 0))


def _sync(f: SyncFact) -> Task | None:
    detail = f"{f.reference}" + (f" from {f.supplier}" if f.supplier else "")
    detail += " is saved on this phone. Stock is not updated until you confirm it."
    action = TaskAction(type="retry_upload", label="Retry upload", target=f"app://sync/retry?task={f.key}")
    return _task(f, Category.SYNC, Urgency.URGENT, f"{f.label} did not upload", detail,
                 f"{f.attempts} attempts failed", action, f.value_paise)


def _close(f: CloseFact) -> Task | None:
    action = TaskAction(type="scan_report", label="Scan sales report", target="app://sales-reports/scan")
    if f.missed_dates:
        n = len(f.missed_dates)
        if n == 1:
            d = f.missed_dates[0]
            title = f"Sales report missing for {d.day} {d.strftime('%b')}"
        else:
            title = f"Sales reports missing for {n} days"
        return _task(f, Category.CLOSE, Urgency.URGENT, title,
                     "Stock is only reduced after a sales report is confirmed.", "Report missing", action,
                     days_overdue=n)
    if not f.report_confirmed_today and f.past_usual_time:
        return _task(f, Category.CLOSE, Urgency.SOON, "Today\u2019s sales report is not submitted",
                     "Stock is only reduced after you scan and confirm the report.", "Due tonight", action)
    return None


_RULES = {
    ExpiryFact: _expiry,
    LowStockFact: _low_stock,
    RefillFact: _refill,
    CreditFact: _credit,
    DeliveryFact: _delivery,
    SyncFact: _sync,
    CloseFact: _close,
}


def build_task(fact: Fact) -> Task | None:
    """Return a task for the fact, or None when nothing needs the owner's attention."""
    return _RULES[type(fact)](fact)


def rank(tasks: list[Task]) -> list[Task]:
    """Highest score first. Equal scores are ordered by key so the order never flickers."""
    return sorted(tasks, key=lambda t: (-t.score, t.key))
