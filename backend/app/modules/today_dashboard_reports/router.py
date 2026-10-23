"""API router for Today Dashboard & Reports (Member 11).

Routes are scoped by store: /api/v1/stores/{store_id}/dashboard/...
"""

import re
from datetime import date, datetime, timedelta

from asyncpg.exceptions import PostgresError
from fastapi import APIRouter, Depends, Path, Query

from . import reports
from .deps import CurrentUser, get_now, get_pool, get_repo, get_sources, require_store_access
from .errors import ApiError, ApiErrorRoute
from .repository import TaskState, TaskStateRepo
from .schemas import (
    Category,
    DailySummary,
    DailySummaryConfirmation,
    PurchaseRegisterResponse,
    SnoozeRequest,
    StockNow,
    TaskStateResponse,
    TodayResponse,
    TrendResponse,
)
from .service import IST, build_today
from .sources import TaskSource

router = APIRouter(route_class=ApiErrorRoute, tags=["Today Dashboard & Reports"])

TASK_KEY = re.compile(r"^[a-z_]+:[A-Za-z0-9_\-]+$")
MAX_SNOOZE_DAYS = 30


def _valid_key(task_key: str) -> str:
    if not TASK_KEY.match(task_key):
        raise ApiError(400, "INVALID_TASK_KEY", "Task key must look like 'expiry:batch_8812'.")
    return task_key


@router.get("/stores/{store_id}/dashboard/today", response_model=TodayResponse)
async def get_today(
    store_id: str,
    category: list[Category] | None = Query(default=None, description="Only return these categories."),
    include_hidden: bool = Query(default=False, description="Also return snoozed and done tasks."),
    user: CurrentUser = Depends(require_store_access),
    now: datetime = Depends(get_now),
    sources: list[TaskSource] = Depends(get_sources),
    repo: TaskStateRepo = Depends(get_repo),
) -> TodayResponse:
    """Ranked tasks for today. If some sources fail, the rest are returned and `source_status` says which failed."""
    return await build_today(
        store_id=store_id, role=user.role, now=now, sources=sources, repo=repo,
        categories=category, include_hidden=include_hidden,
    )


@router.post("/stores/{store_id}/dashboard/tasks/{task_key}/snooze", response_model=TaskStateResponse)
async def snooze_task(
    store_id: str,
    task_key: str,
    body: SnoozeRequest,
    user: CurrentUser = Depends(require_store_access),
    now: datetime = Depends(get_now),
    repo: TaskStateRepo = Depends(get_repo),
) -> TaskStateResponse:
    """Hide a task until the given date. Repeating the same request changes nothing."""
    _valid_key(task_key)
    today = now.astimezone(IST).date()
    if body.until <= today or body.until > today + timedelta(days=MAX_SNOOZE_DAYS):
        raise ApiError(400, "INVALID_SNOOZE_DATE", f"Choose a date after today and within {MAX_SNOOZE_DAYS} days.")
    state = TaskState(store_id, task_key, "snoozed", user.user_id, now, body.until)
    await repo.set_state(state)
    return TaskStateResponse(task_key=task_key, status="snoozed", snoozed_until=body.until,
                             acted_by=user.user_id, acted_at=now.astimezone(IST))


@router.post("/stores/{store_id}/dashboard/tasks/{task_key}/done", response_model=TaskStateResponse)
async def done_task(
    store_id: str,
    task_key: str,
    user: CurrentUser = Depends(require_store_access),
    now: datetime = Depends(get_now),
    repo: TaskStateRepo = Depends(get_repo),
) -> TaskStateResponse:
    """Mark a task done for today. It returns tomorrow if the condition still exists."""
    _valid_key(task_key)
    await repo.set_state(TaskState(store_id, task_key, "done", user.user_id, now))
    return TaskStateResponse(task_key=task_key, status="done", acted_by=user.user_id, acted_at=now.astimezone(IST))


@router.get("/stores/{store_id}/dashboard/reports/daily-summary", response_model=DailySummary)
async def get_daily_summary(
    store_id: str,
    date_param: date | None = Query(default=None, alias="date", description="Day in IST. Defaults to today."),
    user: CurrentUser = Depends(require_store_access),
    now: datetime = Depends(get_now),
    pool=Depends(get_pool),
) -> DailySummary:
    """One day's confirmed figures, keyed by report date (not confirmation date)."""
    if pool is None:
        day = date_param or now.astimezone(IST).date()
        return DailySummary(summary_date=day, confirmed=False, note="Database not configured.")
    try:
        return await reports.daily_summary(pool, store_id, date_param or now.astimezone(IST).date())
    except PostgresError:
        return DailySummary(
            summary_date=date_param or now.astimezone(IST).date(),
            confirmed=False,
            note="The summaries table could not be read right now.",
        )


@router.get("/stores/{store_id}/dashboard/reports/trend", response_model=TrendResponse)
async def get_trend(
    store_id: str,
    user: CurrentUser = Depends(require_store_access),
    now: datetime = Depends(get_now),
    pool=Depends(get_pool),
) -> TrendResponse:
    """Confirmed sales and purchases for the last 7 days; missing days are null."""
    if pool is None:
        return TrendResponse(points=[], error="Database not configured")
    try:
        return await reports.trend(pool, store_id, now.astimezone(IST).date())
    except PostgresError:
        return TrendResponse(points=[], error="Could not read trend data")


@router.get("/stores/{store_id}/dashboard/reports/stock-now", response_model=StockNow)
async def get_stock_now(
    store_id: str,
    user: CurrentUser = Depends(require_store_access),
    now: datetime = Depends(get_now),
    pool=Depends(get_pool),
) -> StockNow:
    """Stock health right now from the inventory module's tables, or available=False until they are merged."""
    if pool is None:
        return StockNow(available=False, note="Database not configured.")
    try:
        return await reports.stock_now(pool, store_id, now.astimezone(IST).date())
    except PostgresError:
        return StockNow(available=False, note="Inventory tables could not be read right now.")


@router.get("/stores/{store_id}/dashboard/reports/purchase-register", response_model=PurchaseRegisterResponse)
async def get_purchase_register(
    store_id: str,
    q: str = Query(default="", max_length=100, description="Search invoice number or supplier."),
    limit: int = Query(default=50, ge=1, le=100),
    offset: int = Query(default=0, ge=0),
    user: CurrentUser = Depends(require_store_access),
    pool=Depends(get_pool),
) -> PurchaseRegisterResponse:
    """Confirmed supplier invoices only. available=False until Members 3/4's tables are merged."""
    if pool is None:
        return PurchaseRegisterResponse(available=False, note="Database not configured.")
    try:
        return await reports.purchase_register(
            pool, store_id, q.strip() or None, limit=limit, offset=offset
        )
    except PostgresError:
        return PurchaseRegisterResponse(
            available=False,
            note="Purchase tables exist but could not be read with the expected columns.",
        )


@router.post("/stores/{store_id}/dashboard/reports/confirm-summary", response_model=DailySummary)
async def confirm_daily_summary(
    body: DailySummaryConfirmation,
    store_id: str = Path(..., min_length=1, max_length=32),
    user: CurrentUser = Depends(require_store_access),
    now: datetime = Depends(get_now),
    pool=Depends(get_pool),
) -> DailySummary:
    """Confirm explicit, non-negative totals once for the current business day."""
    if user.role != "owner":
        raise ApiError(403, "ROLE_FORBIDDEN", "Only a store owner may confirm daily totals.")
    if pool is None:
        day = now.astimezone(IST).date()
        return DailySummary(summary_date=day, confirmed=False, note="Database not configured.")
    try:
        return await reports.write_daily_summary(
            pool,
            store_id,
            now.astimezone(IST).date(),
            body.total_sales_paise,
            body.total_purchases_paise,
            body.udhaar_collected_paise,
            body.udhaar_issued_paise,
            body.expired_stock_value_paise,
            body.low_stock_sku_count,
        )
    except reports.SummaryConflictError as exc:
        raise ApiError(409, "SUMMARY_ALREADY_CONFIRMED", str(exc)) from exc
    except PostgresError:
        day = now.astimezone(IST).date()
        return DailySummary(
            summary_date=day,
            confirmed=False,
            note="The summaries table could not be written right now.",
        )


@router.post("/stores/{store_id}/dashboard/tasks/{task_key}/reopen", response_model=TaskStateResponse)
async def reopen_task(
    store_id: str,
    task_key: str,
    user: CurrentUser = Depends(require_store_access),
    repo: TaskStateRepo = Depends(get_repo),
) -> TaskStateResponse:
    """Bring a snoozed or done task back now."""
    _valid_key(task_key)
    await repo.clear_state(store_id, task_key)
    return TaskStateResponse(task_key=task_key, status="open")
