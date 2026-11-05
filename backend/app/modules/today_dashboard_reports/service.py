"""Builds the Today response: fans out to sources, applies the engine, applies task state."""

import asyncio
from datetime import date, datetime, timedelta, timezone

from .engine import build_task, rank
from .facts import CreditFact, ExpiryFact, Fact, LowStockFact
from .repository import TaskState, TaskStateRepo
from .schemas import Category, Counts, Glance, SourceStatus, Task, TodayResponse
from .sources import TaskSource

IST = timezone(timedelta(hours=5, minutes=30))  # India has no daylight saving
SOURCE_TIMEOUT_SECONDS = 1.5


def is_hidden(state: TaskState | None, today: date) -> str | None:
    """Return 'snoozed' or 'done' if the task should be hidden today, else None.

    - snoozed: hidden until the chosen date (that date itself shows the task again).
    - done: hidden for the rest of the business day it was marked done. If the condition
      still exists tomorrow, the task shows again (for example, a debt still unpaid).
    """
    if state is None:
        return None
    if state.status == "snoozed" and state.snoozed_until and state.snoozed_until > today:
        return "snoozed"
    if state.status == "done" and state.acted_at.astimezone(IST).date() == today:
        return "done"
    return None


async def collect_facts(
    sources: list[TaskSource], store_id: str, now: datetime
) -> tuple[dict[str, list[Fact]], list[SourceStatus]]:
    """Ask every source in parallel. A slow or failing source never breaks the others."""

    async def one(src: TaskSource):
        try:
            facts = await asyncio.wait_for(src.fetch(store_id, now), timeout=SOURCE_TIMEOUT_SECONDS)
            return src.name, facts, SourceStatus(source=src.name, ok=True)
        except asyncio.TimeoutError:
            return src.name, None, SourceStatus(source=src.name, ok=False, error="timeout")
        except Exception:  # noqa: BLE001 - one source must never take the screen down
            return src.name, None, SourceStatus(source=src.name, ok=False, error="unavailable")

    results = await asyncio.gather(*(one(s) for s in sources))
    by_source = {name: facts for name, facts, _ in results if facts is not None}
    return by_source, [status for _, _, status in results]


def _glance(by_source: dict[str, list[Fact]], can_see_money: bool) -> Glance:
    # MOCK-STAGE NOTE: these are derived from the same facts as the tasks. Replace with the
    # stock-health figures from Members 5 and 6 so the totals cover all stock, not just tasks.
    g = Glance()
    inv = by_source.get("inventory")
    if inv is not None:
        g.expiring_30_days_value_paise = sum(f.value_paise for f in inv if isinstance(f, ExpiryFact) and f.days_to_expiry <= 30)
        g.items_below_minimum = sum(1 for f in inv if isinstance(f, LowStockFact))
    credit = by_source.get("credit")
    if credit is not None and can_see_money:
        g.credit_to_collect_paise = sum(f.balance_paise for f in credit if isinstance(f, CreditFact))
    return g


async def build_today(
    *,
    store_id: str,
    role: str,
    now: datetime,
    sources: list[TaskSource],
    repo: TaskStateRepo,
    categories: list[Category] | None = None,
    include_hidden: bool = False,
) -> TodayResponse:
    can_see_money = role == "owner"
    by_source, statuses = await collect_facts(sources, store_id, now)

    tasks: list[Task] = []
    for facts in by_source.values():
        for fact in facts:
            task = build_task(fact)
            if task is None:
                continue
            if task.category is Category.CREDIT and not can_see_money:
                continue  # staff never receive credit balances, even in the API response
            tasks.append(task)

    states = {s.task_key: s for s in await repo.list_states(store_id)}
    today = now.astimezone(IST).date()
    counts = Counts()
    visible: list[Task] = []
    for task in rank(tasks):
        hidden = is_hidden(states.get(task.key), today)
        if hidden == "snoozed":
            counts.snoozed += 1
        elif hidden == "done":
            counts.done_today += 1
        else:
            setattr(counts, task.urgency.value, getattr(counts, task.urgency.value) + 1)
        if hidden and not include_hidden:
            continue
        if categories and task.category not in categories:
            continue
        task.state = hidden or "open"
        visible.append(task)

    return TodayResponse(
        generated_at=now.astimezone(IST),
        counts=counts,
        glance=_glance(by_source, can_see_money),
        tasks=visible,
        source_status=statuses,
    )
