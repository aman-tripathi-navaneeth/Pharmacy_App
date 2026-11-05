from contextlib import asynccontextmanager
import logging

from fastapi import FastAPI, HTTPException
from fastapi.middleware.cors import CORSMiddleware

from app.api.router import api_router
from app.core.config import get_settings
from app.core.database import close_database_engine, get_async_engine, ping_database
from app.core.errors import install_error_handlers
from app.db.postgres import close_postgres_pool, create_postgres_pool

settings = get_settings()
logger = logging.getLogger("pharmacy.api")


@asynccontextmanager
async def lifespan(app: FastAPI):
    app.state.pg_pool = None
    app.state.db_engine = None

    if settings.DATABASE_URL.strip():
        try:
            app.state.pg_pool = await create_postgres_pool()
        except Exception:
            logger.exception("Could not connect to PostgreSQL pool")
        try:
            app.state.db_engine = get_async_engine(settings.sqlalchemy_database_url)
        except Exception:
            logger.exception("Could not initialize SQLAlchemy engine")
    else:
        logger.error(
            "DATABASE_URL is not configured; database routes will return 503"
        )

    try:
        yield
    finally:
        await close_postgres_pool()
        await close_database_engine()


app = FastAPI(title=settings.app_name, version="0.1.0", lifespan=lifespan)
install_error_handlers(app)
app.add_middleware(
    CORSMiddleware,
    allow_origins=settings.parsed_cors_origins,
    allow_credentials=True,
    allow_methods=["GET", "POST", "PUT", "PATCH", "DELETE", "OPTIONS"],
    allow_headers=["Authorization", "Content-Type", "Idempotency-Key"],
)


@app.get("/health", tags=["System"])
async def health() -> dict[str, str]:
    return {"status": "ok"}


@app.get("/ready", tags=["System"])
async def ready() -> dict[str, str]:
    pool = getattr(app.state, "pg_pool", None)
    engine = getattr(app.state, "db_engine", None)

    if pool is None and engine is None:
        code = (
            "DATABASE_NOT_CONFIGURED"
            if not settings.DATABASE_URL.strip()
            else "DATABASE_UNAVAILABLE"
        )
        raise HTTPException(
            status_code=503,
            detail={
                "code": code,
                "message": "PostgreSQL is not connected. Configure DATABASE_URL and start PostgreSQL.",
            },
        )

    if pool is not None:
        try:
            async with pool.acquire() as connection:
                await connection.fetchval("SELECT 1")
            return {"status": "ready", "database": settings.DATABASE_URL.rsplit("/", 1)[-1]}
        except Exception as error:
            logger.exception("PostgreSQL pool readiness check failed")

    if engine is not None:
        health_info = await ping_database(engine)
        if health_info.get("status") == "healthy":
            return {"status": "ready", "database": "postgresql"}

    raise HTTPException(
        status_code=503,
        detail={
            "code": "DATABASE_UNAVAILABLE",
            "message": "PostgreSQL readiness check failed.",
        },
    )


# Mount routes under both /api and /api/v1 for seamless cross-module compatibility
app.include_router(api_router, prefix=settings.api_prefix)
if settings.api_v1_prefix != settings.api_prefix:
    app.include_router(api_router, prefix=settings.api_v1_prefix)
