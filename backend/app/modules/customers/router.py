from typing import Any

from fastapi import APIRouter, Depends, Query

from app.common.deps import get_current_user, get_db
from app.common.store_scope import resolve_store_id
from app.db.serialize import serialize
from app.modules.customers import service
from app.modules.customers.schemas import CreateCustomerIn, PaymentIn, UpdateCustomerIn

router = APIRouter(prefix="/customers", tags=["Customers"])


@router.get("")
async def list_customers(
    storeId: str | None = Query(default=None),
    search: str | None = Query(default=None),
    user: dict[str, Any] = Depends(get_current_user),
    db: Any = Depends(get_db),
) -> Any:
    store_id = await resolve_store_id(db, user, storeId)
    return serialize({"items": await service.list_customers(db, store_id, search)})


@router.post("", status_code=201)
async def create_customer(
    payload: CreateCustomerIn,
    storeId: str | None = Query(default=None),
    user: dict[str, Any] = Depends(get_current_user),
    db: Any = Depends(get_db),
) -> Any:
    store_id = await resolve_store_id(db, user, storeId)
    customer = await service.create_customer(
        db,
        store_id,
        str(user["sub"]),
        name=payload.name,
        phone=payload.phone,
        notes=payload.notes,
    )
    return serialize({"customer": customer})


@router.get("/{customer_id}")
async def get_customer(
    customer_id: str,
    storeId: str | None = Query(default=None),
    user: dict[str, Any] = Depends(get_current_user),
    db: Any = Depends(get_db),
) -> Any:
    store_id = await resolve_store_id(db, user, storeId)
    return serialize(await service.customer_detail(db, store_id, customer_id))


@router.patch("/{customer_id}")
async def update_customer(
    customer_id: str,
    payload: UpdateCustomerIn,
    storeId: str | None = Query(default=None),
    user: dict[str, Any] = Depends(get_current_user),
    db: Any = Depends(get_db),
) -> Any:
    store_id = await resolve_store_id(db, user, storeId)
    customer = await service.update_customer(
        db, store_id, customer_id, payload.model_dump(exclude_unset=True)
    )
    return serialize({"customer": customer})


@router.delete("/{customer_id}")
async def delete_customer(
    customer_id: str,
    storeId: str | None = Query(default=None),
    user: dict[str, Any] = Depends(get_current_user),
    db: Any = Depends(get_db),
) -> dict[str, str]:
    store_id = await resolve_store_id(db, user, storeId)
    await service.delete_customer(db, store_id, customer_id, str(user["sub"]))
    return {"message": "Customer removed"}


@router.post("/{customer_id}/payments", status_code=201)
async def record_payment(
    customer_id: str,
    payload: PaymentIn,
    storeId: str | None = Query(default=None),
    user: dict[str, Any] = Depends(get_current_user),
    db: Any = Depends(get_db),
) -> Any:
    store_id = await resolve_store_id(db, user, storeId)
    customer = await service.record_payment(
        db,
        store_id,
        customer_id,
        str(user["sub"]),
        payload.amount,
        payload.note,
    )
    return serialize({"customer": customer})
