from typing import Any

from fastapi import APIRouter, Depends, Query

from app.common.deps import get_db, require_roles
from app.db.serialize import serialize
from app.modules.audit import service

router = APIRouter(prefix="/audit", tags=["Audit"])


@router.get("")
async def list_audit(
    user_id: str | None = Query(default=None, alias="userId"),
    action: str | None = Query(default=None),
    limit: str | None = Query(default=None),
    user: dict[str, Any] = Depends(require_roles("SUPER_ADMIN")),
    db: Any = Depends(get_db),
) -> Any:
    try:
        parsed_limit = int(limit) if limit else 0
    except ValueError:
        parsed_limit = 0
    capped_limit = min(parsed_limit, 200) if parsed_limit > 0 else 100
    items = await service.list_for(
        db,
        user_id=user_id.strip() if user_id else None,
        action=action.strip() if action else None,
        limit=capped_limit,
    )
    return serialize({"count": len(items), "items": items, "requestedBy": str(user["sub"])})
