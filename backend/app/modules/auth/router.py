from typing import Any

from fastapi import APIRouter, Depends, Request

from app.common.deps import get_current_user, get_db
from app.db.serialize import serialize
from app.modules.auth import service
from app.modules.auth.schemas import (
    ChangePasswordIn,
    ChangeTemporaryPasswordIn,
    ContactVerificationRequestIn,
    ContactVerificationVerifyIn,
    LoginIn,
    RefreshIn,
)

router = APIRouter(prefix="/auth", tags=["Authentication"])


@router.post("/login")
async def login(payload: LoginIn, request: Request, db: Any = Depends(get_db)) -> Any:
    ip = request.client.host if request.client else None
    return serialize(await service.login(db, payload.identifier, payload.password, ip))


@router.post("/refresh")
async def refresh(payload: RefreshIn, db: Any = Depends(get_db)) -> Any:
    return serialize(await service.refresh(db, payload.refreshToken))


@router.post("/logout")
async def logout(
    user: dict[str, Any] = Depends(get_current_user),
    db: Any = Depends(get_db),
) -> dict[str, str]:
    await service.logout(db, user.get("sid"), str(user["sub"]))
    return {"message": "Signed out"}


@router.get("/me")
async def me(
    user: dict[str, Any] = Depends(get_current_user),
    db: Any = Depends(get_db),
) -> Any:
    return serialize(await service.me(db, str(user["sub"])))


@router.post("/owner/change-temporary-password")
async def change_temporary_password(
    payload: ChangeTemporaryPasswordIn,
    user: dict[str, Any] = Depends(get_current_user),
    db: Any = Depends(get_db),
) -> Any:
    return serialize(
        await service.change_temporary_password(
            db, str(user["sub"]), payload.newPassword, payload.confirmPassword
        )
    )


@router.post("/contact-verification/request")
async def request_verification(
    _payload: ContactVerificationRequestIn,
    user: dict[str, Any] = Depends(get_current_user),
    db: Any = Depends(get_db),
) -> Any:
    return serialize(await service.request_contact_verification(db, str(user["sub"])))


@router.post("/contact-verification/verify")
async def verify_contact(
    payload: ContactVerificationVerifyIn,
    user: dict[str, Any] = Depends(get_current_user),
    db: Any = Depends(get_db),
) -> Any:
    return serialize(await service.verify_contact(db, str(user["sub"]), payload.code))


@router.post("/change-password")
async def change_password(
    payload: ChangePasswordIn,
    user: dict[str, Any] = Depends(get_current_user),
    db: Any = Depends(get_db),
) -> dict[str, str]:
    await service.change_password(
        db,
        str(user["sub"]),
        payload.currentPassword,
        payload.newPassword,
        payload.confirmPassword,
        user.get("sid"),
    )
    return {"message": "Password updated. Other sessions signed out."}
