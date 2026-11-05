"""PostgreSQL database connection and session management."""
import json
from typing import Any

import asyncpg

from app.core.config import get_settings

settings = get_settings()

# Module-level pool so both the app lifespan and service helpers see one instance.
_pool: asyncpg.Pool | None = None


async def _init_connection(conn: asyncpg.Connection) -> None:
    """Decode json/jsonb columns straight into Python objects."""
    await conn.set_type_codec(
        "jsonb",
        encoder=json.dumps,
        decoder=json.loads,
        schema="pg_catalog",
    )


async def create_postgres_pool() -> asyncpg.Pool:
    """Create a PostgreSQL connection pool and remember it for the process."""
    global _pool
    dsn = getattr(settings, "asyncpg_url", settings.DATABASE_URL)
    _pool = await asyncpg.create_pool(
        dsn,
        min_size=1,
        max_size=20,
        command_timeout=15,
        init=_init_connection,
    )
    return _pool


async def get_postgres_pool() -> asyncpg.Pool | None:
    """Get the existing PostgreSQL pool, or None if not initialized."""
    return _pool


async def close_postgres_pool() -> None:
    """Close the PostgreSQL connection pool."""
    global _pool
    if _pool is not None:
        await _pool.close()
        _pool = None


async def get_pg_connection(db: Any = None) -> asyncpg.Pool:
    """Resolve the PostgreSQL pool for a request or for a service helper.

    Service helpers receive whatever ``get_db`` returned, which is already the
    pool; request handlers pass the ``Request`` object. Both shapes work here.
    """
    if isinstance(db, asyncpg.Pool):
        return db

    state = getattr(getattr(db, "app", None), "state", None)
    request_pool = getattr(state, "pg_pool", None) if state is not None else None
    if request_pool is not None:
        return request_pool

    if _pool is None:
        raise RuntimeError(
            "PostgreSQL connection pool is not initialized. "
            "Set DATABASE_URL and start the app through app.main:app."
        )
    return _pool
