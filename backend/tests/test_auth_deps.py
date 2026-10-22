import asyncio
from types import SimpleNamespace
from uuid import uuid4

import pytest
from fastapi.security import HTTPAuthorizationCredentials

from app.common.deps import get_current_user
from app.common.security import encode_access_token
from app.core.errors import ApiError


class FakePool:
    def __init__(self, session_is_valid: bool = True) -> None:
        self.session_is_valid = session_is_valid
        self.user_id = uuid4()
        self.session_id = uuid4()

    async def fetchrow(self, _query: str, _user_id: str) -> dict[str, object]:
        return {
            "id": self.user_id,
            "role": "SHOP_OWNER",
            "status": "ACTIVE",
            "owner_store_id": uuid4(),
            "must_change_password": False,
            "plan": None,
        }

    async def fetchval(
        self, _query: str, _session_id: str, _user_id: str
    ) -> bool:
        return self.session_is_valid


def _get_current_user(pool: FakePool) -> dict[str, object]:
    token = encode_access_token(
        {
            "sub": str(pool.user_id),
            "sid": str(pool.session_id),
            "role": "SUPER_ADMIN",
        }
    )
    request = SimpleNamespace(
        app=SimpleNamespace(state=SimpleNamespace(pg_pool=pool))
    )
    credentials = HTTPAuthorizationCredentials(
        scheme="Bearer",
        credentials=token,
    )
    return asyncio.run(get_current_user(request, credentials))


def test_current_user_uses_postgres_account_and_session() -> None:
    pool = FakePool()

    user = _get_current_user(pool)

    assert user["role"] == "SHOP_OWNER"
    assert user["storeId"]
    assert user["mustChangePassword"] is False


def test_current_user_rejects_revoked_or_expired_session() -> None:
    with pytest.raises(ApiError) as error:
        _get_current_user(FakePool(session_is_valid=False))

    assert error.value.status_code == 401
    assert error.value.code == "UNAUTHENTICATED"
