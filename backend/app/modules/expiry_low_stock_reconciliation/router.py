
from datetime import date, datetime, timezone, timedelta

from fastapi import APIRouter, HTTPException, Query, Request

router = APIRouter()


def _database(request: Request):
    db = getattr(request.app.state, "db", None)
    if db is None:
        raise HTTPException(
            status_code=503,
            detail={
                "code": "DATABASE_NOT_CONFIGURED",
                "message": "MongoDB is not configured",
            },
        )
    return db


def _service_unavailable(code: str, message: str):
    raise HTTPException(
        status_code=503,
        detail={"code": code, "message": message},
    )


def _expiry_status(expiry_date, today, critical_days, warning_days):
    if isinstance(expiry_date, datetime):
        expiry_day = expiry_date.date()
    elif isinstance(expiry_date, date):
        expiry_day = expiry_date
    elif isinstance(expiry_date, str):
        try:
            expiry_day = date.fromisoformat(expiry_date.strip()[:10])
        except ValueError:
            return "NO_EXPIRY", None
    else:
        return "NO_EXPIRY", None

    days_left = (expiry_day - today).days

    if days_left < 0:
        return "EXPIRED", days_left
    if days_left <= critical_days:
        return "CRITICAL", days_left
    if days_left <= warning_days:
        return "WARNING", days_left
    return "OK", days_left


async def _expiry_rows(db, store_id):
    settings = await db.stock_settings.find_one(
        {"store_id": store_id}
    ) or {}

    critical_days = int(settings.get("expiry_critical_days", 30))
    warning_days = int(settings.get("expiry_warning_days", 90))

    if critical_days < 0 or warning_days < critical_days:
        raise HTTPException(
            status_code=500,
            detail={
                "code": "INVALID_EXPIRY_SETTINGS",
                "message": "Expiry thresholds are configured incorrectly",
            },
        )

    today = datetime.now(
        timezone(timedelta(hours=5, minutes=30))
    ).date()
    rows = []

    async for batch in db.batches.find({"store_id": store_id}):
        product = await db.products.find_one(
            {"_id": batch.get("product_id")}
        )
        if product is None:
            continue

        balance = await db.stock_balances.find_one({
            "store_id": store_id,
            "batch_id": batch.get("_id"),
            "product_id": batch.get("product_id"),
        }) or {}

        expiry_date = batch.get("expiry_date")
        status, days_left = _expiry_status(
            expiry_date, today, critical_days, warning_days
        )

        if isinstance(expiry_date, (datetime, date)):
            expiry_output = expiry_date.isoformat()
        elif isinstance(expiry_date, str):
            try:
                expiry_output = date.fromisoformat(
                    expiry_date.strip()[:10]
                ).isoformat()
            except ValueError:
                expiry_output = None
        else:
            expiry_output = None

        quantity = float(balance.get("quantity_base", 0) or 0)
        pack_size = int(product.get("pack_size_base", 0) or 0)

        rows.append({
            "batch_id": str(batch.get("_id", "")),
            "product_id": str(batch.get("product_id", "")),
            "product_name": product.get("name", "Unknown product"),
            "batch_number": batch.get("batch_number", ""),
            "expiry_date": expiry_output,
            "days_left": days_left,
            "status": status,
            "quantity_base": quantity,
            "base_unit": product.get("base_unit", ""),
            "pack_equivalent": (
                f"{quantity / pack_size:g} "
                f"{product.get('pack_unit', 'pack')}"
                if pack_size > 0 else None
            ),
        })

    return rows


@router.get("/stores/{store_id}/inventory/expiry/summary")
async def expiry_summary(store_id: str, request: Request):
    rows = await _expiry_rows(_database(request), store_id)

    counts = {
        "expired": 0,
        "critical": 0,
        "warning": 0,
        "ok": 0,
        "no_expiry": 0,
    }
    keys = {
        "EXPIRED": "expired",
        "CRITICAL": "critical",
        "WARNING": "warning",
        "OK": "ok",
        "NO_EXPIRY": "no_expiry",
    }

    for row in rows:
        counts[keys[row["status"]]] += 1

    return counts


@router.get("/stores/{store_id}/inventory/expiry")
async def expiry_list(
    store_id: str,
    request: Request,
    status: list[str] | None = Query(default=None),
    q: str | None = Query(default=None, max_length=100),
    page: int = Query(default=1, ge=1),
    page_size: int = Query(default=20, ge=1, le=100),
):
    allowed = {"EXPIRED", "CRITICAL", "WARNING", "OK", "NO_EXPIRY"}

    if status and any(value not in allowed for value in status):
        raise HTTPException(
            status_code=422,
            detail={
                "code": "INVALID_EXPIRY_STATUS",
                "message": "One or more expiry statuses are invalid",
            },
        )

    rows = await _expiry_rows(_database(request), store_id)

    if status:
        selected = set(status)
        rows = [row for row in rows if row["status"] in selected]

    if q and q.strip():
        term = q.strip().casefold()
        rows = [
            row for row in rows
            if term in row["product_name"].casefold()
            or term in row["batch_number"].casefold()
        ]

    rows.sort(key=lambda row: (
        row["expiry_date"] is None,
        row["expiry_date"] or "",
        row["product_name"].casefold(),
    ))

    total = len(rows)
    start = (page - 1) * page_size

    return {"items": rows[start:start + page_size], "total": total}


def _low_stock_threshold(product, settings):
    """Return a configured threshold in base units, or None if unspecified."""
    for key in (
        "reorder_level_base",
        "minimum_stock_base",
        "min_stock_level_base",
    ):
        value = product.get(key)
        if value is not None:
            try:
                threshold = float(value)
                return threshold if threshold >= 0 else None
            except (TypeError, ValueError):
                return None

    product_id = str(product.get("_id", ""))
    thresholds = settings.get("low_stock_thresholds", {})
    if isinstance(thresholds, dict) and product_id in thresholds:
        try:
            threshold = float(thresholds[product_id])
            return threshold if threshold >= 0 else None
        except (TypeError, ValueError):
            return None

    return None


async def _low_stock_rows(db, store_id):
    settings = await db.stock_settings.find_one(
        {"store_id": store_id}
    ) or {}

    totals = {}
    async for balance in db.stock_balances.find({"store_id": store_id}):
        product_id = balance.get("product_id")
        if product_id is None:
            continue
        try:
            quantity = float(balance.get("quantity_base", 0) or 0)
        except (TypeError, ValueError):
            continue

        key = str(product_id)
        totals[key] = totals.get(key, 0.0) + quantity

    rows = []
    async for product in db.products.find({}):
        product_id = product.get("_id")
        if product_id is None:
            continue

        threshold = _low_stock_threshold(product, settings)
        if threshold is None:
            continue

        quantity = totals.get(str(product_id), 0.0)
        if quantity <= threshold:
            rows.append({
                "product_id": str(product_id),
                "product_name": product.get("name", "Unknown product"),
                "quantity_base": quantity,
                "reorder_level_base": threshold,
                "base_unit": product.get("base_unit", ""),
                "shortage_base": max(0.0, threshold - quantity),
                "status": "OUT_OF_STOCK" if quantity <= 0 else "LOW_STOCK",
            })

    rows.sort(key=lambda row: (
        row["quantity_base"] - row["reorder_level_base"],
        row["product_name"].casefold(),
    ))
    return rows


@router.get("/stores/{store_id}/inventory/low-stock")
async def low_stock_list(
    store_id: str,
    request: Request,
    q: str | None = Query(default=None, max_length=100),
    page: int = Query(default=1, ge=1),
    page_size: int = Query(default=20, ge=1, le=100),
):
    db = _database(request)
    rows = await _low_stock_rows(db, store_id)

    if q and q.strip():
        term = q.strip().casefold()
        rows = [
            row for row in rows
            if term in row["product_name"].casefold()
        ]

    total = len(rows)
    start = (page - 1) * page_size
    return {"items": rows[start:start + page_size], "total": total}


@router.get("/stores/{store_id}/inventory/low-stock/summary")
async def low_stock_summary(store_id: str, request: Request):
    rows = await _low_stock_rows(_database(request), store_id)
    return {
        "low_stock": len(rows),
        "out_of_stock": sum(
            row["status"] == "OUT_OF_STOCK" for row in rows
        ),
        "products": len(rows),
        "thresholds_configured": len(rows),
    }


@router.get("/stores/{store_id}/inventory/reconciliation")
async def reconciliation_status(store_id: str, request: Request):
    _database(request)
    _service_unavailable(
        "INVENTORY_SERVICE_UNAVAILABLE",
        "Reconciliation is unavailable because the inventory movement "
        "service has not been implemented. No stock was changed.",
    )
