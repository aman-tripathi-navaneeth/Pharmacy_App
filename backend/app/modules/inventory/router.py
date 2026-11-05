from typing import Any

from fastapi import APIRouter, Depends, File, Query, UploadFile

from app.common.deps import get_current_user, get_db
from app.common.store_scope import resolve_store_id
from app.core.errors import ApiError
from app.db.serialize import serialize
from app.modules.inventory import service, templates
from app.modules.inventory.schemas import (
    AdjustStockIn,
    BulkInventoryIn,
    CreateInventoryItemIn,
    ImportTemplateIn,
    UpdateInventoryItemIn,
)

router = APIRouter(prefix="/inventory", tags=["Inventory"])


@router.get("/items")
async def list_items(
    search: str | None = None,
    storeId: str | None = Query(default=None),
    user: dict[str, Any] = Depends(get_current_user),
    db: Any = Depends(get_db),
) -> Any:
    store_id = await resolve_store_id(db, user, storeId)
    items = await service.list_items(db, store_id, search)
    for item in items:
        item["low_stock"] = int(item.get("quantity") or 0) <= int(
            item.get("reorder_level") or 0
        )
    return serialize({"items": items})


@router.post("/items", status_code=201)
async def create_item(
    payload: CreateInventoryItemIn,
    user: dict[str, Any] = Depends(get_current_user),
    db: Any = Depends(get_db),
) -> Any:
    store_id = await resolve_store_id(db, user, payload.storeId)
    item = await service.create_item(
        db, store_id, str(user["sub"]), payload.model_dump(exclude={"storeId"})
    )
    return serialize({"item": item})


@router.post("/items/bulk", status_code=201)
async def bulk_create_items(
    payload: BulkInventoryIn,
    storeId: str | None = Query(default=None),
    user: dict[str, Any] = Depends(get_current_user),
    db: Any = Depends(get_db),
) -> Any:
    requested_ids = {
        item.storeId for item in payload.items if item.storeId is not None
    }
    if len(requested_ids) > 1:
        raise ApiError(400, "SHOP_MISMATCH", "All inventory lines must use one shop")
    requested_store_id = storeId or next(iter(requested_ids), None)
    store_id = await resolve_store_id(db, user, requested_store_id)
    result = await service.bulk_create_items(
        db,
        store_id,
        str(user["sub"]),
        [item.model_dump(exclude={"storeId"}) for item in payload.items],
    )
    return serialize(result)


@router.get("/stock-summary")
async def stock_summary(
    storeId: str | None = Query(default=None),
    user: dict[str, Any] = Depends(get_current_user),
    db: Any = Depends(get_db),
) -> Any:
    store_id = await resolve_store_id(db, user, storeId)
    return serialize(await service.stock_summary(db, store_id))


@router.get("/templates")
async def list_templates(
    _user: dict[str, Any] = Depends(get_current_user),
    _db: Any = Depends(get_db),
) -> dict[str, Any]:
    return {
        "templates": [templates.describe(template) for template in templates.TEMPLATES]
    }


@router.post("/import-template")
async def import_template(
    payload: ImportTemplateIn,
    user: dict[str, Any] = Depends(get_current_user),
    db: Any = Depends(get_db),
) -> Any:
    store_id = await resolve_store_id(db, user, payload.storeId)
    return serialize(
        await service.import_template(
            db,
            store_id,
            str(user["sub"]),
            template_id=payload.templateId,
            selling_price=payload.sellingPrice,
            batch_number=payload.batchNumber,
            default_quantity=payload.quantity,
            expiry_months_ahead=payload.expiryMonthsAhead,
            selected_barcodes=payload.selectedBarcodes,
            barcode_overrides=payload.itemBarcodes,
        )
    )


@router.post("/scan-bill")
async def scan_bill(
    file: UploadFile = File(...),
    storeId: str | None = Query(default=None),
    user: dict[str, Any] = Depends(get_current_user),
    db: Any = Depends(get_db),
) -> Any:
    if file.content_type is None or not file.content_type.startswith("image/"):
        raise ApiError(400, "INVALID_FILE_TYPE", "Choose an image file")
    data = await file.read(10 * 1024 * 1024 + 1)
    if len(data) > 10 * 1024 * 1024:
        raise ApiError(400, "FILE_TOO_LARGE", "Image must be 10 MB or smaller")
    store_id = await resolve_store_id(db, user, storeId)
    result = await service.scan_bill_image(db, store_id, str(user["sub"]), data)
    result["lines"] = result.pop("items")
    return serialize(result)


@router.get("/items/{item_id}")
async def get_item(
    item_id: str,
    storeId: str | None = Query(default=None),
    user: dict[str, Any] = Depends(get_current_user),
    db: Any = Depends(get_db),
) -> Any:
    store_id = await resolve_store_id(db, user, storeId)
    return serialize({"item": await service.find_item(db, store_id, item_id)})


@router.patch("/items/{item_id}")
async def update_item(
    item_id: str,
    payload: UpdateInventoryItemIn,
    storeId: str | None = Query(default=None),
    user: dict[str, Any] = Depends(get_current_user),
    db: Any = Depends(get_db),
) -> Any:
    store_id = await resolve_store_id(db, user, storeId)
    item = await service.update_item(
        db, store_id, str(user["sub"]), item_id, payload.model_dump(exclude_unset=True)
    )
    return serialize({"item": item})


@router.delete("/items/{item_id}")
async def archive_item(
    item_id: str,
    storeId: str | None = Query(default=None),
    user: dict[str, Any] = Depends(get_current_user),
    db: Any = Depends(get_db),
) -> dict[str, str]:
    store_id = await resolve_store_id(db, user, storeId)
    await service.archive_item(db, store_id, str(user["sub"]), item_id)
    return {"message": "Inventory item archived"}


@router.post("/items/{item_id}/adjust")
async def adjust_stock(
    item_id: str,
    payload: AdjustStockIn,
    storeId: str | None = Query(default=None),
    user: dict[str, Any] = Depends(get_current_user),
    db: Any = Depends(get_db),
) -> Any:
    store_id = await resolve_store_id(db, user, storeId)
    item = await service.adjust_stock(
        db,
        store_id,
        str(user["sub"]),
        item_id,
        payload.type,
        payload.quantity,
        payload.reason,
    )
    return serialize({"item": item})


@router.get("/items/{item_id}/movements")
async def list_movements(
    item_id: str,
    storeId: str | None = Query(default=None),
    user: dict[str, Any] = Depends(get_current_user),
    db: Any = Depends(get_db),
) -> Any:
    store_id = await resolve_store_id(db, user, storeId)
    await service.find_item(db, store_id, item_id)
    return serialize({"items": await service.list_movements(db, store_id, item_id)})
