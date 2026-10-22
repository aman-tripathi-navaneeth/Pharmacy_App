from typing import Any

from fastapi import APIRouter, Depends, Query

from app.common.deps import get_current_user, get_db
from app.common.store_scope import resolve_store_id
from app.db.serialize import serialize
from app.modules.reports import service

router = APIRouter(prefix="/reports", tags=["Reports"])


@router.get("/overview")
async def overview(
    storeId: str | None = Query(default=None),
    date: str | None = Query(default=None),
    user: dict[str, Any] = Depends(get_current_user),
    db: Any = Depends(get_db),
) -> Any:
    store_id = await resolve_store_id(db, user, storeId)
    return serialize(await service.overview(db, store_id, date))
