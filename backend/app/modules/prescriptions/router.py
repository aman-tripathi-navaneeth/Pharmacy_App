from typing import Any

from fastapi import APIRouter, Body, Depends, Query
from pydantic import BaseModel, Field

from app.common.deps import get_current_user, get_db
from app.core.errors import ApiError
from app.db.serialize import serialize
from app.modules.prescriptions import service

router = APIRouter(prefix="/prescriptions", tags=["Prescriptions"])

PRESCRIPTION_STATUSES = ("pending", "filled", "cancelled")


class PrescriptionPatch(BaseModel):
    patientName: str | None = Field(default=None, max_length=120)
    patientPhone: str | None = Field(default=None, max_length=20)
    medicineName: str | None = Field(default=None, max_length=160)
    quantity: int | None = Field(default=None, ge=1)
    status: str | None = Field(default=None, max_length=24)
    notes: str | None = Field(default=None, max_length=500)


async def _resolve_shop_id(
    user: dict[str, Any], shop_id: str | None, requested: str | None = None
) -> str:
    """Owners only ever see their own shop; admins must name the shop."""
    if user.get("role") != "SUPER_ADMIN":
        own = str(user.get("storeId") or "")
        if shop_id and own and shop_id != own:
            raise ApiError(400, "SHOP_SCOPE_MISMATCH", "Shop scope mismatch")
        if not own:
            raise ApiError(400, "SHOP_ID_REQUIRED", "shopId is required")
        return own
    resolved = str(requested or shop_id or "")
    if not resolved:
        raise ApiError(400, "SHOP_ID_REQUIRED", "shopId is required")
    return resolved


@router.get("")
async def list_prescriptions(
    shopId: str | None = None,
    user: dict[str, Any] = Depends(get_current_user),
    db: Any = Depends(get_db),
) -> Any:
    shop_id = await _resolve_shop_id(user, shopId)
    return serialize(await service.find_by_shop(db, shop_id))


@router.post("", status_code=201)
async def create_prescription(
    data: dict[str, Any] = Body(...),
    user: dict[str, Any] = Depends(get_current_user),
    db: Any = Depends(get_db),
) -> Any:
    payload = dict(data)
    if user.get("role") != "SUPER_ADMIN" and user.get("storeId"):
        payload["shopId"] = user["storeId"]
    if not payload.get("shopId"):
        raise ApiError(400, "SHOP_ID_REQUIRED", "shopId is required")
    return serialize(
        await service.create(
            db,
            payload,
            actor_id=str(user["sub"]),
            actor_role=str(user.get("role") or "SHOP_OWNER"),
        )
    )


@router.get("/{prescription_id}")
async def get_prescription(
    prescription_id: str,
    shopId: str | None = Query(default=None),
    user: dict[str, Any] = Depends(get_current_user),
    db: Any = Depends(get_db),
) -> Any:
    shop_id = await _resolve_shop_id(user, shopId)
    return serialize({"prescription": await service.find_by_id(db, shop_id, prescription_id)})


@router.patch("/{prescription_id}")
async def update_prescription(
    prescription_id: str,
    payload: PrescriptionPatch,
    shopId: str | None = Query(default=None),
    user: dict[str, Any] = Depends(get_current_user),
    db: Any = Depends(get_db),
) -> Any:
    shop_id = await _resolve_shop_id(user, shopId)
    data = payload.model_dump(exclude_unset=True)
    status = data.get("status")
    if status and status not in PRESCRIPTION_STATUSES:
        raise ApiError(
            400,
            "INVALID_STATUS",
            "status must be pending, filled or cancelled",
        )
    prescription = await service.update(
        db,
        shop_id,
        prescription_id,
        data,
        actor_id=str(user["sub"]),
        actor_role=str(user.get("role") or "SHOP_OWNER"),
    )
    return serialize({"prescription": prescription})


@router.delete("/{prescription_id}")
async def delete_prescription(
    prescription_id: str,
    shopId: str | None = Query(default=None),
    user: dict[str, Any] = Depends(get_current_user),
    db: Any = Depends(get_db),
) -> dict[str, str]:
    shop_id = await _resolve_shop_id(user, shopId)
    await service.delete(
        db,
        shop_id,
        prescription_id,
        actor_id=str(user["sub"]),
        actor_role=str(user.get("role") or "SHOP_OWNER"),
    )
    return {"message": "Prescription removed"}
