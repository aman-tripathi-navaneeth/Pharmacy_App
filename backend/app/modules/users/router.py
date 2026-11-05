from typing import Any

from fastapi import APIRouter, Depends

from app.common.deps import get_current_user, get_db
from app.db.serialize import serialize
from app.modules.auth.schemas import UpdateMeIn
from app.modules.sessions import service as sessions
from app.modules.users import service

router = APIRouter(prefix="/users", tags=["Users"])


@router.get("/me")
async def me(
    user: dict[str, Any] = Depends(get_current_user),
    db: Any = Depends(get_db),
) -> Any:
    doc = await service.find_by_id(db, str(user["sub"]))
    return serialize({"user": service.sanitize_user(doc)})


@router.patch("/me")
async def update_me(
    payload: UpdateMeIn,
    user: dict[str, Any] = Depends(get_current_user),
    db: Any = Depends(get_db),
) -> Any:
    patch: dict[str, Any] = {}
    if payload.fullName:
        patch["fullName"] = payload.fullName.strip()
    if payload.language:
        patch["language"] = payload.language
    if payload.plan:
        patch["plan"] = payload.plan
    if payload.profileImage is not None:
        # An empty value clears the saved photo.
        patch["profileImage"] = payload.profileImage or ""
    if not patch:
        return serialize({"user": service.sanitize_user(await service.find_by_id(db, str(user["sub"])))})
    updated = await service.update_profile_fields(db, str(user["sub"]), patch)
    return serialize({"user": service.sanitize_user(updated)})


@router.get("/me/sessions")
async def list_sessions(
    user: dict[str, Any] = Depends(get_current_user),
    db: Any = Depends(get_db),
) -> Any:
    items = await sessions.list_active_for_user(db, str(user["sub"]))
    result = []
    for session in items:
        session_id = str(session["id"])
        result.append(
            {
                "id": session_id,
                "deviceLabel": session.get("device_label") or "this device",
                "lastUsedAt": session.get("last_used_at") or session.get("created_at"),
                "current": user.get("sid") == session_id,
            }
        )
    return serialize({"items": result})
