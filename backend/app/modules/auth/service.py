import logging
import secrets
from datetime import datetime, timedelta, timezone
from typing import Any

from app.common.identity import is_probably_email, mask_destination, normalize_email, normalize_phone
from app.common.security import (
    encode_access_token,
    generate_temp_password,
    hash_password,
    random_token,
    sha256,
    verify_password,
)
from app.core.config import get_settings
from app.core.errors import ApiError
from app.db.postgres import get_pg_connection
from app.modules.sessions import service as sessions
from app.modules.users import service as users

logger = logging.getLogger("pharmacy.auth")

USER_ROLE_SUPER_ADMIN = "SUPER_ADMIN"
USER_ROLE_SHOP_OWNER = "SHOP_OWNER"
USER_STATUS_INVITED = "INVITED"
USER_STATUS_ACTIVE = "ACTIVE"

# Dev-friendly contact verification codes: user_id -> (code, expires_at)
_OTP_CODES: dict[str, tuple[str, datetime]] = {}


def onboarding_payload(user: dict[str, Any]) -> dict[str, Any]:
    from app.modules.onboarding.service import steps

    payload = steps(user)
    payload["mustChangePassword"] = bool(user.get("must_change_password"))
    return payload


def _session_payload(db: Any, user: dict[str, Any], raw: str, session_id: str) -> dict[str, Any]:
    settings = get_settings()
    token = encode_access_token(
        {
            "sub": str(user["id"]),
            "role": user["role"],
            "storeId": str(user["owner_store_id"] or ""),
            "sid": session_id,
            "mustChangePassword": bool(user.get("must_change_password")),
            "plan": user.get("plan"),
        }
    )
    return {
        "accessToken": token,
        "refreshToken": raw,
        "expiresIn": settings.jwt_access_ttl_seconds,
        "user": users.sanitize_user(user),
        "onboarding": onboarding_payload(user),
    }


async def _issue_tokens(db: Any, user: dict[str, Any], *, revoke_others: bool = False) -> dict[str, Any]:
    settings = get_settings()
    raw, session_id = await sessions.create_session(
        db,
        str(user["id"]),
        str(user["owner_store_id"]) if user.get("owner_store_id") else None,
        settings.jwt_refresh_ttl_days,
    )
    if revoke_others:
        await sessions.revoke_all_for_user_excluding(db, str(user["id"]), session_id)
    await users.touch_last_login(db, str(user["id"]))
    return _session_payload(db, user, raw, session_id)


async def authenticate_user(db: Any, identifier: str, password: str) -> dict[str, Any] | None:
    user = await users.find_by_identifier(db, identifier)
    if not user:
        return None
    password_hash = user.get("password_hash")
    if not password_hash or not verify_password(str(password_hash), password):
        return None
    return user


async def login(db: Any, identifier: str, password: str, ip: Any = None) -> dict[str, Any]:
    user = await authenticate_user(db, identifier, password)
    if not user:
        raise ApiError(401, "INVALID_CREDENTIALS", "Invalid email/mobile or password")
    # Invited owners still set their first password, so those two states may sign in.
    if user.get("status") not in (USER_STATUS_ACTIVE, USER_STATUS_INVITED):
        raise ApiError(403, "ACCOUNT_INACTIVE", "This account is not active yet")
    is_first_login = user.get("last_login_at") is None
    payload = await _issue_tokens(db, user)
    await _audit(db, user, "auth.login", ip)
    if is_first_login:
        await _send_welcome_email(db, user)
    await _send_pending_action_emails(db, user)
    return payload


async def _send_welcome_email(db: Any, user: dict[str, Any]) -> None:
    """Welcome mail the first time an owner signs in."""
    try:
        from app.modules.email import service as email_service
        from app.modules.shops import service as shops

        user_id = str(user["id"])
        store_id = str(user.get("owner_store_id") or "") or None
        shop = await shops.find_by_owner(db, user_id, store_id) if store_id else None
        shop_name = str((shop or {}).get("shop_name") or "your pharmacy")
        recipient_name = str(user.get("full_name") or "there")
        email_address = user.get("email_normalized")

        await email_service.send_first_login_email(
            db,
            to_email=email_address,
            recipient_name=recipient_name,
            shop_name=shop_name,
            store_id=store_id,
            user_id=user_id,
        )
    except Exception:  # email problems must never block a sign-in
        logger.exception("Welcome email failed for %s", user.get("id"))


async def _send_pending_action_emails(db: Any, user: dict[str, Any]) -> None:
    """Remind the user about every step that is still blocking them."""
    try:
        from app.modules.email import service as email_service

        await email_service.send_pending_action_emails(
            db,
            user={"sub": str(user["id"]), "role": user.get("role"), "storeId": user.get("owner_store_id")},
        )
    except Exception:  # email problems must never block a sign-in
        logger.exception("Action-required emails failed for %s", user.get("id"))


async def _audit(db: Any, user: dict[str, Any], action: str, ip: Any = None) -> None:
    from app.modules.audit import service as audit

    try:
        await audit.record(
            db,
            actor_user_id=str(user["id"]),
            actor_role=str(user.get("role") or "UNKNOWN"),
            store_id=str(user["owner_store_id"]) if user.get("owner_store_id") else None,
            action=action,
            target_type="user",
            target_id=str(user["id"]),
            result="SUCCESS",
            ip_address=str(ip) if ip else None,
        )
    except Exception:  # auditing must never break sign-in
        logger.exception("audit write failed for %s", action)


async def refresh(db: Any, refresh_token: str) -> dict[str, Any]:
    session = await sessions.rotate(db, refresh_token)
    user = await users.find_by_id(db, str(session["user_id"]))
    if user.get("status") not in (USER_STATUS_ACTIVE, USER_STATUS_INVITED):
        await sessions.revoke_all_for_user(db, str(user["id"]))
        raise ApiError(401, "SESSION_INVALID", "Session expired, please sign in again")
    new_raw = session["newRawToken"]
    return _session_payload(db, user, new_raw, str(session["id"]))


async def logout(db: Any, session_id: str | None, user_id: str) -> None:
    await sessions.revoke_session(db, session_id)


async def me(db: Any, user_id: str) -> dict[str, Any]:
    user = await users.find_by_id(db, user_id)
    return {"user": users.sanitize_user(user), "onboarding": onboarding_payload(user)}


async def change_temporary_password(
    db: Any, user_id: str, new_password: str, confirm_password: str
) -> dict[str, Any]:
    if new_password != confirm_password:
        raise ApiError(400, "PASSWORD_MISMATCH", "Passwords do not match")
    user = await users.find_by_id(db, user_id)
    if not user.get("must_change_password"):
        raise ApiError(400, "PASSWORD_ALREADY_SET", "Your password is already set")
    updated = await users.set_password(
        db, user_id, hash_password(new_password), must_change_password=False
    )
    if updated.get("status") == USER_STATUS_INVITED:
        updated = await users.update_profile_fields(db, user_id, {"status": USER_STATUS_ACTIVE})
    return await _issue_tokens(db, updated, revoke_others=True)


async def change_password(
    db: Any,
    user_id: str,
    current_password: str,
    new_password: str,
    confirm_password: str,
    session_id: str | None,
) -> None:
    if new_password != confirm_password:
        raise ApiError(400, "PASSWORD_MISMATCH", "Passwords do not match")
    user = await users.find_by_id(db, user_id)
    if not verify_password(str(user.get("password_hash") or ""), current_password):
        raise ApiError(400, "INVALID_PASSWORD", "Current password is incorrect")
    await users.set_password(db, user_id, hash_password(new_password), must_change_password=False)
    await sessions.revoke_all_for_user_excluding(db, user_id, session_id)


async def request_contact_verification(db: Any, user_id: str) -> dict[str, Any]:
    user = await users.find_by_id(db, user_id)
    email = user.get("email_normalized")
    phone = user.get("phone_e164")
    use_email = bool(email)
    destination = str(email or phone or "")
    if not destination:
        raise ApiError(400, "NO_CONTACT_ON_FILE", "Add an email or mobile number first")

    code = secrets.token_hex(4)
    _OTP_CODES[user_id] = (code, datetime.now(timezone.utc) + timedelta(minutes=10))
    logger.info(
        "[DEV-DELIVERY] %s OTP -> %s : code = %s",
        "email" if use_email else "sms",
        destination,
        code,
    )
    response: dict[str, Any] = {
        "channel": "email" if use_email else "sms",
        "destination": mask_destination(destination),
    }
    if get_settings().is_development:
        response["devCode"] = code
    return response


async def verify_contact(db: Any, user_id: str, code: str) -> dict[str, Any]:
    entry = _OTP_CODES.get(user_id)
    if not entry or entry[0] != code.strip().lower():
        raise ApiError(400, "INVALID_CODE", "That verification code is not valid")
    if entry[1] < datetime.now(timezone.utc):
        _OTP_CODES.pop(user_id, None)
        raise ApiError(400, "CODE_EXPIRED", "That code has expired, request a new one")
    _OTP_CODES.pop(user_id, None)
    user = await users.find_by_id(db, user_id)
    updated = await users.mark_contact_verified(db, user_id, use_email=bool(user.get("email_normalized")))
    return {"user": users.sanitize_user(updated), "onboarding": onboarding_payload(updated)}


async def issue_recovery_credential(
    db: Any,
    user_id: str,
    actor_id: str,
    actor_role: str,
    new_temp_password: str | None = None,
) -> dict[str, Any]:
    user = await users.find_by_id(db, user_id)
    temp_password = new_temp_password or generate_temp_password()
    await users.set_password(
        db, user_id, hash_password(temp_password), must_change_password=True
    )
    await sessions.revoke_all_for_user(db, user_id)

    from app.modules.audit import service as audit

    await audit.record(
        db,
        actor_user_id=actor_id,
        actor_role=actor_role or "UNKNOWN",
        store_id=str(user.get("owner_store_id")) if user.get("owner_store_id") else None,
        action="admin.users.recovery",
        target_type="user",
        target_id=user_id,
        result="SUCCESS",
    )
    destination = str(user.get("email_normalized") or user.get("phone_e164") or "")
    logger.info(
        "[DEV-DELIVERY] PASSWORD RECOVERY -> %s : temporary password = %s",
        destination,
        temp_password,
    )
    await _send_recovery_email(db, user, temp_password, destination)
    return {
        "destination": mask_destination(destination) if destination else "registered contact",
        "tempPassword": temp_password,
    }


async def _send_recovery_email(
    db: Any, user: dict[str, Any], temp_password: str, destination: str
) -> None:
    """Email the fresh temporary password after a reset or re-issue."""
    try:
        from app.modules.email import service as email_service
        from app.modules.shops import service as shops

        user_id = str(user["id"])
        store_id = str(user.get("owner_store_id") or "") or None
        shop = await shops.find_by_owner(db, user_id, store_id) if store_id else None
        await email_service.send_credentials_email(
            db,
            to_email=user.get("email_normalized"),
            recipient_name=str(user.get("full_name") or "there"),
            temp_password=temp_password,
            login_hint=destination,
            shop_name=str((shop or {}).get("shop_name") or "your pharmacy"),
            store_id=store_id,
            user_id=user_id,
            reason="A new temporary password was issued for your account",
        )
    except Exception:  # email problems must never block a credential reset
        logger.exception("Recovery email failed for %s", user.get("id"))


# Re-exported so routers/other modules keep the previous import surface.
__all__ = [
    "authenticate_user",
    "change_password",
    "change_temporary_password",
    "generate_temp_password",
    "hash_password",
    "issue_recovery_credential",
    "login",
    "logout",
    "me",
    "onboarding_payload",
    "random_token",
    "refresh",
    "request_contact_verification",
    "sha256",
    "verify_contact",
    "verify_password",
]
