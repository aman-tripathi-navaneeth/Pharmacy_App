"""Shared JSON snapshot builder used by the admin export endpoint."""

from datetime import datetime, timezone
from typing import Any

from app.db.postgres import get_pg_connection

PROJECT_TABLES = [
    "users",
    "shops",
    "sessions",
    "inventory_items",
    "stock_movements",
    "customers",
    "customer_payments",
    "bills",
    "prescriptions",
    "notifications",
    "email_logs",
    "issues",
    "audit_logs",
    "suppliers",
    "purchase_orders",
    "purchase_order_items",
    "invitations",
]

SECRET_FIELDS = {"password_hash", "refresh_token_hash", "token_hash", "passwordHash", "refreshTokenHash", "tokenHash"}


def redact(value: Any) -> Any:
    """Remove secret hash fields while preserving the rest of the row."""
    if isinstance(value, dict):
        return {key: redact(item) for key, item in value.items() if key not in SECRET_FIELDS}
    if isinstance(value, list):
        return [redact(item) for item in value]
    return value


async def build_snapshot(db: Any, database: str, *, include_secrets: bool = False) -> dict[str, Any]:
    """Read every project table and return a serializable snapshot."""
    pool = await get_pg_connection(db)
    tables: dict[str, list[dict[str, Any]]] = {}
    for name in PROJECT_TABLES:
        rows = await pool.fetch(f"SELECT * FROM {name} LIMIT 5000")
        documents = [dict(row) for row in rows]
        tables[name] = documents if include_secrets else [redact(doc) for doc in documents]
    counts = {name: len(docs) for name, docs in tables.items()}
    return {
        "database": database,
        "exportedAt": datetime.now(timezone.utc),
        "secretsIncluded": include_secrets,
        "collections": tables,
        "counts": counts,
        "totalDocuments": sum(counts.values()),
    }
