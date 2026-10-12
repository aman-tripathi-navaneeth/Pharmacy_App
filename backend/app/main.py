from contextlib import asynccontextmanager
from typing import Any

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from pymongo import AsyncMongoClient

from app.api.v1.router import api_router
from app.core.config import get_settings
from app.db.mongo import create_mongo_client

settings = get_settings()


@asynccontextmanager
async def lifespan(app: FastAPI):
    app.state.mongo_client = None
    app.state.db = None
    if settings.mongodb_url.strip():
        client: AsyncMongoClient[dict[str, Any]] = create_mongo_client(settings.mongodb_url)
        app.state.mongo_client = client
        app.state.db = client[settings.mongodb_database]
    try:
        yield
    finally:
        if app.state.mongo_client is not None:
            await app.state.mongo_client.close()


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
    if app.state.db is None:
        from fastapi import HTTPException

        raise HTTPException(status_code=503, detail={"code": "DATABASE_NOT_CONFIGURED", "message": "Set MONGODB_URL to enable database access"})
    await app.state.mongo_client.admin.command("ping")
    return {"status": "ready", "database": settings.mongodb_database}


app.include_router(api_router, prefix=settings.api_v1_prefix)
