import asyncio
from urllib.parse import urlsplit

import asyncpg

from app.core.config import BACKEND_DIR, get_settings


async def initialize_database() -> None:
    settings = get_settings()
    if not settings.DATABASE_URL.strip():
        raise RuntimeError("Set DATABASE_URL in backend/.env before initializing PostgreSQL.")

    schema = (BACKEND_DIR / "schema.sql").read_text(encoding="utf-8")
    connection = await asyncpg.connect(settings.DATABASE_URL, command_timeout=30)
    try:
        await connection.execute(schema)
        await connection.fetchval("SELECT 1")
    finally:
        await connection.close()

    database = urlsplit(settings.DATABASE_URL).path.lstrip("/")
    print(f"PostgreSQL schema initialized for {database}.")


if __name__ == "__main__":
    asyncio.run(initialize_database())
