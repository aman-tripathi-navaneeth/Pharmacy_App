import re
from collections.abc import AsyncGenerator
from typing import Any

from sqlalchemy import text
from sqlalchemy.ext.asyncio import (
    AsyncEngine,
    AsyncSession,
    async_sessionmaker,
    create_async_engine,
)
from sqlalchemy.orm import DeclarativeBase

from app.core.config import get_settings


class Base(DeclarativeBase):
    """Base declarative model for all PostgreSQL relational tables."""
    pass


# Global engine and sessionmaker singletons
_async_engine: AsyncEngine | None = None
_async_session_factory: async_sessionmaker[AsyncSession] | None = None


def mask_db_url(url: str) -> str:
    """Masks database credentials for secure logging."""
    if not url:
        return "<unconfigured>"
    return re.sub(r"://([^:]+):([^@]+)@", r"://\1:***@", url)


def get_async_engine(database_url: str | None = None) -> AsyncEngine:
    """Initializes or returns the global AsyncEngine."""
    global _async_engine, _async_session_factory
    if _async_engine is not None and database_url is None:
        return _async_engine

    target_url = database_url or get_settings().database_url
    if not target_url.strip():
        # Fallback to in-memory async SQLite for local/offline testing if unconfigured
        target_url = "sqlite+aiosqlite:///:memory:"

    # Connect args: asyncpg or aiosqlite specific
    connect_args: dict[str, Any] = {}
    if target_url.startswith("sqlite"):
        connect_args["check_same_thread"] = False

    engine = create_async_engine(
        target_url,
        echo=False,
        future=True,
        pool_pre_ping=True,
        connect_args=connect_args,
    )

    if database_url is None:
        _async_engine = engine
        _async_session_factory = async_sessionmaker(
            bind=_async_engine,
            class_=AsyncSession,
            expire_on_commit=False,
            autoflush=False,
        )

    return engine


def get_session_factory() -> async_sessionmaker[AsyncSession]:
    """Returns the configured session factory."""
    global _async_session_factory
    if _async_session_factory is None:
        get_async_engine()
    assert _async_session_factory is not None
    return _async_session_factory


async def get_db_session() -> AsyncGenerator[AsyncSession, None]:
    """FastAPI dependency yielding an isolated AsyncSession per request."""
    factory = get_session_factory()
    async with factory() as session:
        try:
            yield session
        except Exception:
            await session.rollback()
            raise
        finally:
            await session.close()


async def ping_database(engine: AsyncEngine | None = None) -> dict[str, Any]:
    """Executes a simple SELECT 1 query to verify database health."""
    active_engine = engine or get_async_engine()
    try:
        async with active_engine.connect() as conn:
            result = await conn.execute(text("SELECT 1"))
            val = result.scalar()
            return {
                "status": "healthy" if val == 1 else "unexpected_result",
                "dialect": active_engine.dialect.name,
                "url": mask_db_url(str(active_engine.url)),
            }
    except Exception as exc:
        return {
            "status": "unhealthy",
            "error": str(exc),
            "dialect": active_engine.dialect.name if active_engine else "unknown",
            "url": mask_db_url(str(active_engine.url)) if active_engine else "<none>",
        }


async def close_database_engine() -> None:
    """Gracefully shuts down connection pools."""
    global _async_engine, _async_session_factory
    if _async_engine is not None:
        await _async_engine.dispose()
        _async_engine = None
        _async_session_factory = None
