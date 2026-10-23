from contextlib import asynccontextmanager

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from app.api.v1.router import api_router
from app.core.config import get_settings
from app.db.postgres import create_pool, database_name

settings = get_settings()


@asynccontextmanager
async def lifespan(app: FastAPI):
    app.state.pg_pool = None
    if settings.postgres_url.strip():
        # Run `alembic upgrade head` first so the schema exists (see backend/alembic/).
        app.state.pg_pool = await create_pool(settings.postgres_url)
    try:
        yield
    finally:
        if app.state.pg_pool is not None:
            await app.state.pg_pool.close()


app = FastAPI(title=settings.app_name, version="0.1.0", lifespan=lifespan)
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
    if app.state.pg_pool is None:
        from fastapi import HTTPException

        raise HTTPException(status_code=503, detail={"code": "DATABASE_NOT_CONFIGURED", "message": "Set POSTGRES_URL to enable database access"})
    await app.state.pg_pool.fetchval("SELECT 1")
    return {"status": "ready", "database": database_name(settings.postgres_url)}


app.include_router(api_router, prefix=settings.api_v1_prefix)
