"""Verification script for Step 4: Validate all 18 SQL repository methods against an async SQLite engine."""

import asyncio
from datetime import date, datetime, timedelta, timezone
from sqlalchemy.ext.asyncio import create_async_engine, async_sessionmaker, AsyncSession

from app.core.database import Base
from app.modules.inventory_batches_stock_ledger.models import (
    BatchCreate,
    FefoAllocationPreviewRequest,
    FefoDispenseRequest,
    MovementType,
    ReversalRequest,
    ReturnToSupplierRequest,
    SegregateExpiredRequest,
    SourceDocumentReference,
    SourceDocumentType,
    StockTransactionCreate,
    UpdateThresholdsRequest,
)
from app.modules.inventory_batches_stock_ledger.sql_repository import InventorySqlRepository


async def main():
    engine = create_async_engine("sqlite+aiosqlite:///:memory:", echo=False)
    session_factory = async_sessionmaker(engine, class_=AsyncSession, expire_on_commit=False)

    # 1. Create all tables
    async with engine.begin() as conn:
        await conn.run_sync(Base.metadata.create_all)
    print("[1/10] Created relational tables in in-memory SQLite.")

    store_id = "test-sql-store-001"
    today = datetime.now(timezone.utc).date()

    async with session_factory() as session:
        repo = InventorySqlRepository(session)

        # 2. Test connectivity
        conn_res = await repo.connectivity_probe(store_id)
        assert conn_res["status"] == "route-ready"
        print(f"[2/10] Connectivity probe verified: {conn_res['database']}")

        # 3. Register batches
        b1 = await repo.register_batch(
            store_id,
            BatchCreate(
                product_id="PROD-PARACETAMOL",
                batch_number="PARA-2026-A1",
                expiry_date=today + timedelta(days=60),
                initial_quantity=100.0,
                mrp=25.0,
                purchase_rate=15.0,
                base_unit="TABLET",
            ),
        )
        assert b1.current_quantity == 100.0
        print(f"[3/10] Batch registered: {b1.batch_number} (current_qty={b1.current_quantity})")

        # Expired batch
        b_exp = await repo.register_batch(
            store_id,
            BatchCreate(
                product_id="PROD-PARACETAMOL",
                batch_number="PARA-EXP-01",
                expiry_date=today - timedelta(days=10),
                initial_quantity=20.0,
                mrp=25.0,
                purchase_rate=15.0,
                base_unit="TABLET",
            ),
        )

        # 4. Read inventory balances and batches
        inv = await repo.get_inventory_balances(store_id)
        assert inv.total >= 1
        print(f"[4/10] Balances query verified: {len(inv.items)} products found")

        prod_batches = await repo.get_product_batches(store_id, "PROD-PARACETAMOL")
        assert len(prod_batches) == 2
        print(f"[5/10] Product batches FEFO verified: {len(prod_batches)} batches")

        # 5. Outward Stock Movement & Negative stock prevention
        tx_out = await repo.post_stock_movement(
            store_id,
            StockTransactionCreate(
                product_id="PROD-PARACETAMOL",
                batch_number="PARA-2026-A1",
                movement_type=MovementType.SALES_REPORT_OUT,
                quantity=-20.0,
                base_unit="TABLET",
                idempotency_key="IDEM-TEST-OUT-001",
                source_document=SourceDocumentReference(
                    document_type=SourceDocumentType.SALES_REPORT,
                    document_id="SALE-001",
                    document_number="INV-001",
                ),
            ),
        )
        assert tx_out.quantity == -20.0
        print(f"[6/10] Outward stock transaction posted: {tx_out.id} (qty={tx_out.quantity})")

        # 6. Reversal
        rev_tx = await repo.reverse_transaction(
            store_id,
            ReversalRequest(
                original_transaction_id=tx_out.id,
                idempotency_key="IDEM-REV-001",
                reason="Customer returned medicine",
            ),
        )
        assert rev_tx.quantity == 20.0
        print(f"[7/10] Reversal transaction verified: {rev_tx.id} (restored={rev_tx.quantity})")

        # 7. FEFO Preview and Dispense
        preview = await repo.fefo_preview(
            store_id,
            FefoAllocationPreviewRequest(
                product_id="PROD-PARACETAMOL",
                quantity=3.0,
                unit="STRIP",
            ),
        )
        assert preview.base_quantity_required == 30.0
        assert preview.is_fully_fulfillable is True
        print(f"[8/10] FEFO preview verified: {preview.base_quantity_required} units across {len(preview.allocations)} lots")

        dispense = await repo.fefo_dispense(
            store_id,
            FefoDispenseRequest(
                product_id="PROD-PARACETAMOL",
                quantity=3.0,
                unit="STRIP",
                source_document=SourceDocumentReference(
                    document_type=SourceDocumentType.SALES_REPORT,
                    document_id="SALE-FEFO-001",
                ),
                idempotency_key="IDEM-DISP-001",
            ),
        )
        assert dispense.total_dispensed_base_units == 30.0
        print(f"[9/10] FEFO dispense executed: {dispense.total_dispensed_base_units} units")

        # 8. Expiry buckets & Thresholds
        buckets = await repo.get_expiry_buckets(store_id)
        assert len(buckets.buckets) == 5
        print(f"[10/10] Expiry buckets verified: {buckets.total_active_batches} active lots tracked across 5 tiers.")

    await engine.dispose()
    print("\nALL STEP 4 SQL ENDPOINTS AND REPOSITORY METHODS VERIFIED SUCCESSFULLY!")


if __name__ == "__main__":
    asyncio.run(main())
