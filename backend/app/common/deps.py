from typing import Any, Callable
from uuid import UUID

import jwt
from fastapi import Depends, HTTPException, Request
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer

from app.common.security import decode_access_token
from app.core.errors import ApiError

bearer_scheme = HTTPBearer(auto_error=False)


async def get_current_user(
    request: Request,
    credentials: HTTPAuthorizationCredentials | None = Depends(bearer_scheme),
) -> dict[str, Any]:
    if credentials is None or not credentials.credentials:
        raise ApiError(401, "UNAUTHENTICATED", "Sign in to continue")
    try:
        payload = decode_access_token(credentials.credentials)
    except jwt.PyJWTError:
        raise ApiError(401, "UNAUTHENTICATED", "Sign in to continue") from None
    if not payload.get("sub"):
        raise ApiError(401, "UNAUTHENTICATED", "Invalid token")

    pool = getattr(request.app.state, "pg_pool", None)
    if pool is None:
        raise HTTPException(
            status_code=503,
            detail={
                "code": "DATABASE_UNAVAILABLE",
                "message": "PostgreSQL is not connected.",
            },
        )
    try:
        user_id = str(UUID(str(payload["sub"])))
        session_id = str(UUID(str(payload["sid"])))
    except (KeyError, ValueError, TypeError, AttributeError):
        raise ApiError(401, "UNAUTHENTICATED", "Invalid token") from None

    account = await pool.fetchrow(
        """SELECT id, role, status, owner_store_id, must_change_password, plan
           FROM users WHERE id = $1""",
        user_id,
    )
    if account is None or account["status"] not in ("ACTIVE", "INVITED"):
        raise ApiError(401, "UNAUTHENTICATED", "Sign in to continue")
    session_is_valid = await pool.fetchval(
        """SELECT EXISTS(
             SELECT 1 FROM sessions
             WHERE id = $1 AND user_id = $2
               AND revoked_at IS NULL AND expires_at > NOW()
           )""",
        session_id,
        user_id,
    )
    if not session_is_valid:
        raise ApiError(401, "UNAUTHENTICATED", "Session expired, please sign in again")

    payload["role"] = str(account["role"])
    payload["mustChangePassword"] = bool(account["must_change_password"])
    payload["plan"] = account["plan"]
    store_id = str(account["owner_store_id"] or "")
    if store_id:
        payload["storeId"] = store_id
    else:
        payload.pop("storeId", None)
    return payload


def require_roles(*roles: str) -> Callable[..., Any]:
    async def _guard(user: dict[str, Any] = Depends(get_current_user)) -> dict[str, Any]:
        if user.get("role") not in roles:
            raise ApiError(403, "FORBIDDEN_ROLE", "You do not have permission for this action")
        return user

    return _guard


async def get_db(request: Request):
    """Return the PostgreSQL pool attached to the running app."""
    pool = getattr(request.app.state, "pg_pool", None)
    if pool is None:
        raise HTTPException(
            status_code=503,
            detail={
                "code": "DATABASE_UNAVAILABLE",
                "message": "PostgreSQL is not connected. Configure DATABASE_URL and start PostgreSQL.",
            },
        )

    return pool
