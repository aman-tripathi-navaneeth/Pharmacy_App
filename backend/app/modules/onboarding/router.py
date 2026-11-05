from typing import Any

from fastapi import APIRouter, Depends

from app.common.deps import get_db, require_roles
from app.db.serialize import serialize
from app.modules.auth.schemas import CompleteProfileIn, CompleteProfileLiteIn
from app.modules.onboarding import service

router = APIRouter(tags=["Onboarding"])
owner_only = require_roles("SHOP_OWNER")


@router.get("/owner/onboarding")
async def get_onboarding(
    user: dict[str, Any] = Depends(owner_only),
    db: Any = Depends(get_db),
) -> Any:
    return serialize(await service.status(db, str(user["sub"])))


@router.post("/owner/profile/complete")
async def complete_profile(
    payload: CompleteProfileIn,
    user: dict[str, Any] = Depends(owner_only),
    db: Any = Depends(get_db),
) -> Any:
    return serialize(
        await service.update_profile(db, str(user["sub"]), user.get("storeId"), payload.model_dump())
    )


@router.post("/onboarding/owner/profile/complete")
async def complete_profile_mobile(
    payload: CompleteProfileLiteIn,
    user: dict[str, Any] = Depends(owner_only),
    db: Any = Depends(get_db),
) -> Any:
    """Alias used by the Flutter onboarding screen."""
    return serialize(
        await service.complete_lite(db, str(user["sub"]), user.get("storeId"), payload.model_dump())
    )
