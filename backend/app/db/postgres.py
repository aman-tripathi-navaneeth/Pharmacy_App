"""Postgres connection pool (asyncpg). Keep credentials on the server only.

The DSN looks like postgresql://user:password@host:5432/dbname (add ?sslmode=require
for hosted providers such as Neon). Schema changes are managed by Alembic: run
`alembic upgrade head` from the backend folder before first use.
"""

from urllib.parse import urlparse

import asyncpg


def database_name(dsn: str) -> str:
    """Extract dbname from the DSN for the /ready endpoint."""
    path = urlparse(dsn).path.lstrip("/")
    return path.partition("?")[0] or "postgres"


async def create_pool(dsn: str) -> asyncpg.Pool:
    """Create the connection pool. Created inside lifespan because it is async."""
    return await asyncpg.create_pool(dsn, min_size=1, max_size=10)
