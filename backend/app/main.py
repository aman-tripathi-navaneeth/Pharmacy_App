from contextlib import asynccontextmanager

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from app.api.v1.router import api_router
from app.core.config import get_settings
from app.core.database import close_database_engine, get_async_engine, ping_database

settings = get_settings()


@asynccontextmanager
async def lifespan(app: FastAPI):
    if settings.database_url.strip():
        app.state.db_engine = get_async_engine(settings.database_url)
    else:
        app.state.db_engine = None

    try:
        yield
    finally:
        await close_database_engine()


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
    if getattr(app.state, "db_engine", None) is None:
        from fastapi import HTTPException

        raise HTTPException(
            status_code=503,
            detail={"code": "DATABASE_NOT_CONFIGURED", "message": "Set DATABASE_URL to enable database access"},
        )
    is_alive = await ping_database(app.state.db_engine)
    if not is_alive:
        from fastapi import HTTPException

        raise HTTPException(
            status_code=503,
            detail={"code": "DATABASE_UNAVAILABLE", "message": "Database ping failed"},
        )
    return {"status": "ready", "database": "postgresql"}


app.include_router(api_router, prefix=settings.api_v1_prefix)
