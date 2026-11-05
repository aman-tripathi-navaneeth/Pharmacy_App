from typing import Any

from fastapi import APIRouter, Depends, Query
from fastapi.responses import HTMLResponse

from app.common.deps import get_current_user, get_db
from app.common.store_scope import resolve_store_id
from app.db.serialize import serialize
from app.modules.bills import service
from app.modules.bills.schemas import CreateBillIn

router = APIRouter(prefix="/bills", tags=["Billing"])


@router.get("")
async def list_bills(
    storeId: str | None = Query(default=None),
    customerId: str | None = Query(default=None),
    date: str | None = Query(default=None),
    limit: int = Query(default=100, ge=1, le=200),
    user: dict[str, Any] = Depends(get_current_user),
    db: Any = Depends(get_db),
) -> Any:
    store_id = await resolve_store_id(db, user, storeId)
    items = await service.list_bills(
        db, store_id, customer_id=customerId, date=date, limit=limit
    )
    return serialize({"items": items})


@router.post("", status_code=201)
async def create_bill(
    payload: CreateBillIn,
    user: dict[str, Any] = Depends(get_current_user),
    db: Any = Depends(get_db),
) -> Any:
    store_id = await resolve_store_id(db, user, payload.storeId)
    bill = await service.create_bill(
        db, store_id, str(user["sub"]), payload.model_dump()
    )
    return serialize({"bill": bill})


@router.get("/{bill_id}")
async def get_bill(
    bill_id: str,
    storeId: str | None = Query(default=None),
    user: dict[str, Any] = Depends(get_current_user),
    db: Any = Depends(get_db),
) -> Any:
    store_id = await resolve_store_id(db, user, storeId)
    return serialize({"bill": await service.find_bill(db, store_id, bill_id)})


@router.get("/{bill_id}/invoice", response_class=HTMLResponse)
async def get_invoice(
    bill_id: str,
    storeId: str | None = Query(default=None),
    user: dict[str, Any] = Depends(get_current_user),
    db: Any = Depends(get_db),
) -> HTMLResponse:
    store_id = await resolve_store_id(db, user, storeId)
    return HTMLResponse(await service.invoice_html(db, store_id, bill_id))
