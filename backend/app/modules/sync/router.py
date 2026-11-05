from typing import Any

from fastapi import APIRouter, Depends
from pydantic import BaseModel, Field

from app.common.deps import get_db, require_roles
from app.core.errors import ApiError
from app.db.serialize import serialize
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
    payload: SyncPushIn,
    user: dict[str, Any] = Depends(sync_roles),
    db: Any = Depends(get_db),
) -> Any:
    return serialize(
        await service.push(
            db,
            _store(user),
            str(user["sub"]),
            [op.model_dump() for op in payload.operations],
        )
    )
