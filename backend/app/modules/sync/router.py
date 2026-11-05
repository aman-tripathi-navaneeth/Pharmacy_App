from typing import Any

from fastapi import APIRouter, Body, Depends
from pydantic import BaseModel, Field

from app.common.deps import get_db, require_roles
from app.core.errors import ApiError
from app.db.serialize import serialize
from app.modules.offline_sync_reliability import service as m12_service
from app.modules.sync import service

router = APIRouter(prefix="/sync", tags=["Offline Sync"])
sync_roles = require_roles("SUPER_ADMIN", "SHOP_OWNER")


class SyncOperation(BaseModel):
    clientRef: str = Field(min_length=4, max_length=120)
    kind: str = "inventory_adjust"
    itemId: str | None = None
    type: str | None = None
    quantity: int | None = None
    reason: str | None = Field(default=None, max_length=200)


class SyncPushIn(BaseModel):
    operations: list[SyncOperation] = Field(default_factory=list, max_length=200)


def _store(user: dict[str, Any]) -> str:
    store_id = str(user.get("storeId") or "")
    if not store_id:
        raise ApiError(400, "SHOP_REQUIRED", "Choose a shop before syncing")
    return store_id


@router.get("/state")
async def sync_state(
    user: dict[str, Any] = Depends(sync_roles),
    db: Any = Depends(get_db),
) -> Any:
    return serialize(await service.state(db, _store(user)))


@router.post("/push")
async def sync_push(
    payload: dict[str, Any] = Body(default_factory=dict),
    user: dict[str, Any] = Depends(sync_roles),
    db: Any = Depends(get_db),
) -> Any:
    ops = payload.get("operations") or []
    # M12 format uses deviceId or clientOperationId
    if "deviceId" in payload or (ops and isinstance(ops[0], dict) and "clientOperationId" in ops[0]):
        store_id = str(payload.get("storeId") or user.get("storeId") or "00000000-0000-4000-9000-000000000001")
        return serialize(m12_service.sync_push_m12(store_id, str(user.get("sub") or ""), payload))
    parsed = SyncPushIn.model_validate(payload)
    return serialize(
        await service.push(
            db,
            _store(user),
            str(user["sub"]),
            [op.model_dump() for op in parsed.operations],
        )
    )
