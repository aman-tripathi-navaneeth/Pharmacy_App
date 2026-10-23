"""FastAPI dependencies for this module.

AUTH IS A DEVELOPMENT STUB until Member 1 publishes the real sign-in and store-access
dependency. Replace get_current_user and require_store_access here, in this one file, and
nothing else in the module needs to change.
"""

from dataclasses import dataclass
from datetime import datetime

from fastapi import Depends, Path, Request

from app.core.config import Settings, get_settings

from .errors import ApiError
from .repository import InMemoryTaskStateRepo, PostgresTaskStateRepo, TaskStateRepo
from .service import IST
from .sources import TaskSource, make_default_sources, make_unavailable_sources


@dataclass
class CurrentUser:
    user_id: str
    role: str  # "owner" or "staff"
    store_ids: frozenset[str]


def get_current_user(request: Request, settings: Settings = Depends(get_settings)) -> CurrentUser:
    """DEV STUB. Reads X-Dev-User, X-Dev-Role and X-Dev-Stores headers. Only works when APP_ENV=development."""
    if settings.app_env != "development":
        raise ApiError(401, "AUTH_NOT_CONFIGURED", "Sign-in is not available yet for this environment.")
    role = request.headers.get("X-Dev-Role", "owner")
    if role not in ("owner", "staff"):
        raise ApiError(403, "ROLE_FORBIDDEN", "Unknown role.")
    stores = request.headers.get("X-Dev-Stores", "demo-store")
    return CurrentUser(
        user_id=request.headers.get("X-Dev-User", "dev-user"),
        role=role,
        store_ids=frozenset(s.strip() for s in stores.split(",") if s.strip()),
    )


def require_store_access(
    store_id: str = Path(..., min_length=1, max_length=32),
    user: CurrentUser = Depends(get_current_user),
) -> CurrentUser:
    """Server-side check that the signed-in user may use this store. Never trust the URL alone.

    max_length=32 matches the lead's fixed schema: store_id VARCHAR(32) on every table.
    """
    if store_id not in user.store_ids:
        raise ApiError(403, "STORE_FORBIDDEN", "You do not have access to this store.")
    return user


def get_now() -> datetime:
    return datetime.now(IST)


def get_pool(request: Request):
    """The shared Postgres pool, or None when no database is configured."""
    return getattr(request.app.state, "pg_pool", None)


def get_sources(request: Request) -> list[TaskSource]:
    """Real Postgres sources when the pool is up; otherwise an empty list, which the
    service treats as every source unavailable - an honest state, never demo data."""
    pool = getattr(request.app.state, "pg_pool", None)
    if pool is None:
        return make_unavailable_sources()
    return make_default_sources(pool)


_memory_repo = InMemoryTaskStateRepo()


def get_repo(request: Request) -> TaskStateRepo:
    """Postgres when POSTGRES_URL is set, otherwise an in-memory store so local work still runs.

    The dashboard_task_state table must already exist: create it with `alembic upgrade head`.
    """
    pool = getattr(request.app.state, "pg_pool", None)
    if pool is None:
        return _memory_repo
    return PostgresTaskStateRepo(pool)
