import asyncio
import warnings
import pytest
from fastapi.testclient import TestClient
from sqlalchemy.ext.asyncio import create_async_engine, async_sessionmaker, AsyncSession
from sqlalchemy.pool import StaticPool

from app.core.database import Base
import app.core.database as db_module
from app.main import app, settings

# Filter upstream starlette testclient deprecation notice
warnings.filterwarnings("ignore", message=".*Using `httpx` with `starlette.testclient` is deprecated.*")


@pytest.fixture(autouse=True)
def isolate_unit_tests_database(monkeypatch: pytest.MonkeyPatch):
    """Isolate baseline unit tests by defaulting database_url to empty string."""
    original_db_url = settings.database_url
    monkeypatch.setattr(settings, "database_url", "")
    yield
    settings.database_url = original_db_url


@pytest.fixture(scope="module")
def live_client():
    """Shared relational SQLite in-memory test client with initialized tables."""
    test_db_url = "sqlite+aiosqlite:///:memory:"
    engine = create_async_engine(
        test_db_url,
        echo=False,
        connect_args={"check_same_thread": False},
        poolclass=StaticPool,
    )
    session_factory = async_sessionmaker(engine, class_=AsyncSession, expire_on_commit=False)

    orig_engine = db_module._async_engine
    orig_factory = db_module._async_session_factory
    db_module._async_engine = engine
    db_module._async_session_factory = session_factory

    async def init_schema():
        async with engine.begin() as conn:
            await conn.run_sync(Base.metadata.create_all)

    asyncio.run(init_schema())

    with TestClient(app) as client:
        client.app.state.db_engine = engine
        yield client

    async def cleanup():
        await engine.dispose()

    asyncio.run(cleanup())
    db_module._async_engine = orig_engine
    db_module._async_session_factory = orig_factory
    app.state.db_engine = None
