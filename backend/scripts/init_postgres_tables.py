"""Script to initialize and verify relational tables for PostgreSQL / SQLite.

Creates all tables defined under Base.metadata:
- batches
- stock_transactions
- stock_balances
- inventory_thresholds

Usage:
    python scripts/init_postgres_tables.py
"""

import asyncio
import os
import sys

# Ensure backend root is on Python path
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from sqlalchemy import inspect
from app.core.config import get_settings
from app.core.database import Base, get_async_engine, mask_db_url
# Import models to register them on Base.metadata
from app.modules.inventory_batches_stock_ledger.models import (
    AuditCountItemTable,
    AuditSessionTable,
    BatchTable,
    InventoryThresholdTable,
    StockBalanceTable,
    StockTransactionTable,
)


async def init_tables(database_url: str | None = None) -> None:
    settings = get_settings()
    target_url = database_url or settings.database_url
    if not target_url.strip():
        target_url = "sqlite+aiosqlite:///pharmacy_store_dev.db"

    print("=" * 70)
    print("Initializing Relational Database Tables (PostgreSQL / SQLite)")
    print(f"Target Database: {mask_db_url(target_url)}")
    print("=" * 70)

    engine = get_async_engine(target_url)

    async with engine.begin() as conn:
        print("[1/3] Creating tables via Base.metadata.create_all...")
        await conn.run_sync(Base.metadata.create_all)
        print("      Created / Verified tables successfully.")

    # Inspect created tables
    print("[2/3] Inspecting created tables...")
    async with engine.connect() as conn:
        def inspect_tables(sync_conn):
            inspector = inspect(sync_conn)
            table_names = inspector.get_table_names()
            return table_names

        tables = await conn.run_sync(inspect_tables)
        print(f"      Tables present in database: {tables}")
        for t in ["batches", "stock_transactions", "stock_balances", "inventory_thresholds", "audit_sessions", "audit_count_items"]:
            if t in tables:
                print(f"      [OK] {t}")
            else:
                print(f"      [FAIL] {t} not found!")

    print("[3/3] Closing connection pool...")
    await engine.dispose()
    print("Database table initialization completed successfully.")


if __name__ == "__main__":
    url_arg = sys.argv[1] if len(sys.argv) > 1 else None
    asyncio.run(init_tables(url_arg))
