from typing import Any

from fastapi import APIRouter, Depends
from pydantic import BaseModel, Field

from app.common.deps import get_db, require_roles
from app.db.serialize import serialize
from app.modules.suppliers import service

router = APIRouter(tags=["Suppliers"])
owner_or_admin = require_roles("SUPER_ADMIN", "SHOP_OWNER")


def _store(user: dict[str, Any]) -> str:
    store_id = str(user.get("storeId") or "")
    if not store_id:
        from app.core.errors import ApiError

        raise ApiError(400, "SHOP_REQUIRED", "Choose a shop before continuing")
    return store_id


class SupplierIn(BaseModel):
    name: str = Field(min_length=2, max_length=160)
    contactName: str | None = Field(default=None, max_length=120)
    phone: str | None = Field(default=None, max_length=20)
    email: str | None = Field(default=None, max_length=160)
    gstin: str | None = Field(default=None, max_length=32)
    address: dict[str, Any] | None = None


class SupplierPatch(BaseModel):
    name: str | None = Field(default=None, min_length=2, max_length=160)
    contactName: str | None = None
    phone: str | None = None
    email: str | None = None
    gstin: str | None = None
    address: dict[str, Any] | None = None
    status: str | None = None


class PurchaseOrderItemIn(BaseModel):
    medicineName: str = Field(min_length=2, max_length=160)
    barcode: str | None = None
    batchNumber: str | None = None
    quantity: int = Field(ge=1)
    unitCost: float = Field(ge=0)
    expiryDate: str | None = None


class PurchaseOrderIn(BaseModel):
    supplierId: str | None = None
    poNumber: str | None = None
    expectedDate: str | None = None
    notes: str | None = Field(default=None, max_length=500)
    items: list[PurchaseOrderItemIn] = Field(min_length=1)


class PurchaseOrderPatch(BaseModel):
    status: str | None = Field(default=None, max_length=24)
    expectedDate: str | None = Field(default=None, max_length=32)
    notes: str | None = Field(default=None, max_length=500)


@router.get("/suppliers")
async def list_suppliers(
    user: dict[str, Any] = Depends(owner_or_admin),
    db: Any = Depends(get_db),
) -> Any:
    return serialize({"items": await service.list_suppliers(db, _store(user))})


@router.post("/suppliers", status_code=201)
async def create_supplier(
    payload: SupplierIn,
    user: dict[str, Any] = Depends(owner_or_admin),
    db: Any = Depends(get_db),
) -> Any:
    supplier = await service.create_supplier(db, _store(user), payload.model_dump())
    return serialize({"supplier": supplier})


@router.get("/suppliers/{supplier_id}")
async def get_supplier(
    supplier_id: str,
    user: dict[str, Any] = Depends(owner_or_admin),
    db: Any = Depends(get_db),
) -> Any:
    return serialize({"supplier": await service.find_supplier(db, _store(user), supplier_id)})


@router.patch("/suppliers/{supplier_id}")
async def update_supplier(
    supplier_id: str,
    payload: SupplierPatch,
    user: dict[str, Any] = Depends(owner_or_admin),
    db: Any = Depends(get_db),
) -> Any:
    supplier = await service.update_supplier(
        db, _store(user), supplier_id, payload.model_dump(exclude_unset=True)
    )
    return serialize({"supplier": supplier})


@router.delete("/suppliers/{supplier_id}")
async def delete_supplier(
    supplier_id: str,
    user: dict[str, Any] = Depends(owner_or_admin),
    db: Any = Depends(get_db),
) -> dict[str, str]:
    await service.delete_supplier(db, _store(user), supplier_id, str(user.get("sub") or ""))
    return {"message": "Supplier archived"}


@router.get("/purchase-orders")
async def list_orders(
    user: dict[str, Any] = Depends(owner_or_admin),
    db: Any = Depends(get_db),
) -> Any:
    return serialize({"items": await service.list_orders(db, _store(user))})


@router.post("/purchase-orders", status_code=201)
async def create_order(
    payload: PurchaseOrderIn,
    user: dict[str, Any] = Depends(owner_or_admin),
    db: Any = Depends(get_db),
) -> Any:
    order = await service.create_order(
        db, _store(user), str(user["sub"]), payload.model_dump()
    )
    return serialize({"purchaseOrder": order})


@router.get("/purchase-orders/{order_id}")
async def get_order(
    order_id: str,
    user: dict[str, Any] = Depends(owner_or_admin),
    db: Any = Depends(get_db),
) -> Any:
    return serialize({"purchaseOrder": await service.find_order(db, _store(user), order_id)})


@router.post("/purchase-orders/{order_id}/receive")
async def receive_order(
    order_id: str,
    user: dict[str, Any] = Depends(owner_or_admin),
    db: Any = Depends(get_db),
) -> Any:
    return serialize(
        await service.receive_order(db, _store(user), str(user["sub"]), order_id)
    )


@router.patch("/purchase-orders/{order_id}")
async def update_order(
    order_id: str,
    payload: PurchaseOrderPatch,
    user: dict[str, Any] = Depends(owner_or_admin),
    db: Any = Depends(get_db),
) -> Any:
    order = await service.update_order(
        db,
        _store(user),
        str(user["sub"]),
        order_id,
        payload.model_dump(exclude_unset=True),
    )
    return serialize({"purchaseOrder": order})


@router.delete("/purchase-orders/{order_id}")
async def delete_order(
    order_id: str,
    user: dict[str, Any] = Depends(owner_or_admin),
    db: Any = Depends(get_db),
) -> dict[str, str]:
    await service.delete_order(db, _store(user), str(user["sub"]), order_id)
    return {"message": "Purchase order removed"}
