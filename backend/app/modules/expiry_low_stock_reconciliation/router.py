from datetime import datetime
from datetime import timezone, timedelta

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


def _expiry_status(expiry_date, today, critical_days, warning_days):
    if not isinstance(expiry_date, datetime):
        return "NO_EXPIRY", None

    days_left = (expiry_date.date() - today).days
    if days_left < 0:
        return "EXPIRED", days_left
    if days_left <= critical_days:
        return "CRITICAL", days_left
    if days_left <= warning_days:
        return "WARNING", days_left
    return "OK", days_left


async def _expiry_rows(db, store_id):
    settings = await db.stock_settings.find_one({"store_id": store_id}) or {}
    critical_days = int(settings.get("expiry_critical_days", 30))
    warning_days = int(settings.get("expiry_warning_days", 90))
    today = datetime.now(timezone(timedelta(hours=5, minutes=30))).date()
    rows = []

    async for batch in db.batches.find({"store_id": store_id}):
        product = await db.products.find_one({"_id": batch.get("product_id")})
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
        quantity = float(balance.get("quantity_base", 0) or 0)
        pack_size = int(product.get("pack_size_base", 0) or 0)

        rows.append({
            "batch_id": str(batch.get("_id", "")),
            "product_id": str(batch.get("product_id", "")),
            "product_name": product.get("name", "Unknown product"),
            "batch_number": batch.get("batch_number", ""),
            "expiry_date": expiry_date.isoformat()
            if isinstance(expiry_date, datetime) else None,
            "days_left": days_left,
            "status": status,
            "quantity_base": quantity,
            "base_unit": product.get("base_unit", ""),
            "pack_equivalent": (
                f"{quantity / pack_size:g} {product.get('pack_unit', 'pack')}"
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
