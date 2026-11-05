"""Automated integration tests for Phase 3: Inventory APIs (Relational)."""

import asyncio
from datetime import date, datetime, timedelta, timezone
import pytest
from fastapi.testclient import TestClient

from app.core.database import get_session_factory
from app.modules.inventory_batches_stock_ledger.models import (
    BatchTable,
    StockBalanceTable,
    StockTransactionTable,
)


@pytest.fixture(scope="module")
def seed_test_data(live_client: TestClient):
    """Seed isolated store inventory data into relational tables for Phase 3 testing."""
    session_factory = get_session_factory()
    test_store = "test-store-p3"
    other_store = "other-store-p3"
    today = datetime.now(timezone.utc).date()

    async def _seed():
        async with session_factory() as session:
            b1 = BatchTable(
                id="B-DOLO-NEAR",
                store_id=test_store,
                product_id="prod-dolo-650",
                batch_number="DOLO-EXP-NEAR",
                expiry_date=today + timedelta(days=30),
                mrp=35.0,
                purchase_rate=20.0,
                current_quantity=50.0,
                base_unit="TABLET",
                is_active=True,
                created_at=datetime.now(timezone.utc),
            )
            b2 = BatchTable(
                id="B-DOLO-FAR",
                store_id=test_store,
                product_id="prod-dolo-650",
                batch_number="DOLO-EXP-FAR",
                expiry_date=today + timedelta(days=365),
                mrp=35.0,
                purchase_rate=20.0,
                current_quantity=100.0,
                base_unit="TABLET",
                is_active=True,
                created_at=datetime.now(timezone.utc),
            )
            b3 = BatchTable(
                id="B-AZI-EXP",
                store_id=test_store,
                product_id="prod-azithral-500",
                batch_number="AZI-EXPIRED",
                expiry_date=today - timedelta(days=10),
                mrp=120.0,
                purchase_rate=80.0,
                current_quantity=5.0,
                base_unit="TABLET",
                is_active=True,
                created_at=datetime.now(timezone.utc),
            )
            b4 = BatchTable(
                id="B-DOLO-OTHER",
                store_id=other_store,
                product_id="prod-dolo-650",
                batch_number="DOLO-OTHER-STORE",
                expiry_date=today + timedelta(days=90),
                mrp=35.0,
                purchase_rate=20.0,
                current_quantity=25.0,
                base_unit="TABLET",
                is_active=True,
                created_at=datetime.now(timezone.utc),
            )
            session.add_all([b1, b2, b3, b4])

            bal1 = StockBalanceTable(
                id=f"{test_store}-prod-dolo-650-DOLO-EXP-NEAR",
                store_id=test_store,
                product_id="prod-dolo-650",
                batch_number="DOLO-EXP-NEAR",
                current_quantity=50.0,
                base_unit="TABLET",
                updated_at=datetime.now(timezone.utc),
            )
            bal2 = StockBalanceTable(
                id=f"{test_store}-prod-dolo-650-DOLO-EXP-FAR",
                store_id=test_store,
                product_id="prod-dolo-650",
                batch_number="DOLO-EXP-FAR",
                current_quantity=100.0,
                base_unit="TABLET",
                updated_at=datetime.now(timezone.utc),
            )
            bal3 = StockBalanceTable(
                id=f"{test_store}-prod-azithral-500-AZI-EXPIRED",
                store_id=test_store,
                product_id="prod-azithral-500",
                batch_number="AZI-EXPIRED",
                current_quantity=5.0,
                base_unit="TABLET",
                updated_at=datetime.now(timezone.utc),
            )
            session.add_all([bal1, bal2, bal3])

            tx1 = StockTransactionTable(
                id="TX-001",
                store_id=test_store,
                product_id="prod-dolo-650",
                batch_number="DOLO-EXP-NEAR",
                movement_type="PURCHASE_IN",
                quantity=50.0,
                base_unit="TABLET",
                entered_quantity=50.0,
                entered_unit="TABLET",
                conversion_factor=1.0,
                source_document={"document_type": "PURCHASE_INVOICE", "document_id": "inv-001"},
                idempotency_key="idemp-tx-001",
                created_at=datetime.now(timezone.utc) - timedelta(hours=2),
            )
            tx2 = StockTransactionTable(
                id="TX-002",
                store_id=test_store,
                product_id="prod-dolo-650",
                batch_number="DOLO-EXP-FAR",
                movement_type="PURCHASE_IN",
                quantity=100.0,
                base_unit="TABLET",
                entered_quantity=100.0,
                entered_unit="TABLET",
                conversion_factor=1.0,
                source_document={"document_type": "PURCHASE_INVOICE", "document_id": "inv-002"},
                idempotency_key="idemp-tx-002",
                created_at=datetime.now(timezone.utc) - timedelta(hours=1),
            )
            tx3 = StockTransactionTable(
                id="TX-003",
                store_id=test_store,
                product_id="prod-dolo-650",
                batch_number="DOLO-EXP-NEAR",
                movement_type="SALES_REPORT_OUT",
                quantity=-10.0,
                base_unit="TABLET",
                entered_quantity=10.0,
                entered_unit="TABLET",
                conversion_factor=1.0,
                source_document={"document_type": "SALES_REPORT", "document_id": "sales-001"},
                idempotency_key="idemp-tx-003",
                created_at=datetime.now(timezone.utc),
            )
            session.add_all([tx1, tx2, tx3])
            await session.commit()

    asyncio.run(_seed())
    yield


# ==============================================================================
# Phase 3 Endpoint Tests
# ==============================================================================


def test_get_inventory_list(live_client: TestClient, seed_test_data) -> None:
    """GET /stores/{store_id}/inventory aggregates stock and supports search."""
    response = live_client.get("/api/v1/stores/test-store-p3/inventory")
    assert response.status_code == 200
    data = response.json()
    assert data["total"] == 2
    assert len(data["items"]) == 2

    # Verify Dolo has 150 total units across 2 active batches
    dolo_item = next(i for i in data["items"] if i["product_id"] == "prod-dolo-650")
    assert dolo_item["total_quantity"] == 150.0
    assert dolo_item["active_batch_count"] == 2
    assert dolo_item["has_expired_batches"] is False

    # 2. Search filtering
    search_res = live_client.get("/api/v1/stores/test-store-p3/inventory?search=azithral")
    assert search_res.status_code == 200
    search_data = search_res.json()
    assert search_data["total"] == 1
    assert search_data["items"][0]["product_id"] == "prod-azithral-500"

    # 3. Low stock filtering (Azithral has 5 units <= 20 threshold)
    low_res = live_client.get("/api/v1/stores/test-store-p3/inventory?low_stock_only=true")
    assert low_res.status_code == 200
    low_data = low_res.json()
    assert low_data["total"] == 1
    assert low_data["items"][0]["product_id"] == "prod-azithral-500"


def test_get_product_batches_fefo_order(live_client: TestClient, seed_test_data) -> None:
    """GET /stores/{store_id}/products/{product_id}/batches returns batches sorted by FEFO."""
    response = live_client.get("/api/v1/stores/test-store-p3/products/prod-dolo-650/batches")
    assert response.status_code == 200
    batches = response.json()
    assert len(batches) == 2

    # First batch must have earlier expiry date (FEFO priority!)
    assert batches[0]["batch_number"] == "DOLO-EXP-NEAR"
    assert batches[1]["batch_number"] == "DOLO-EXP-FAR"
    assert batches[0]["expiry_date"] < batches[1]["expiry_date"]


def test_get_batch_detail_and_isolation(live_client: TestClient, seed_test_data) -> None:
    """GET /stores/{store_id}/batches/{batch_id} fetches detail and enforces store isolation."""
    # 1. Fetch valid batch
    response = live_client.get("/api/v1/stores/test-store-p3/batches/DOLO-EXP-NEAR")
    assert response.status_code == 200
    batch = response.json()
    assert batch["batch_number"] == "DOLO-EXP-NEAR"
    assert batch["current_quantity"] == 50.0

    # 2. Fetch nonexistent batch -> 404
    missing = live_client.get("/api/v1/stores/test-store-p3/batches/NONEXISTENT-BATCH")
    assert missing.status_code == 404
    assert missing.json()["detail"]["code"] == "BATCH_NOT_FOUND"

    # 3. Store isolation: attempt to access batch belonging to other_store from test_store -> 404
    isolation_check = live_client.get("/api/v1/stores/test-store-p3/batches/DOLO-OTHER-STORE")
    assert isolation_check.status_code == 404


def test_get_stock_transactions_ledger(live_client: TestClient, seed_test_data) -> None:
    """GET /stores/{store_id}/inventory/transactions returns reverse chronological ledger."""
    response = live_client.get("/api/v1/stores/test-store-p3/inventory/transactions")
    assert response.status_code == 200
    data = response.json()
    assert data["total"] == 3
    assert len(data["items"]) == 3

    # Newest transaction first (sales report out)
    assert data["items"][0]["movement_type"] == "SALES_REPORT_OUT"
    assert data["items"][0]["quantity"] == -10.0

    # Filter by movement_type
    filtered = live_client.get("/api/v1/stores/test-store-p3/inventory/transactions?movement_type=PURCHASE_IN")
    assert filtered.status_code == 200
    f_data = filtered.json()
    assert f_data["total"] == 2
    assert all(i["movement_type"] == "PURCHASE_IN" for i in f_data["items"])


def test_get_inventory_summary_metrics(live_client: TestClient, seed_test_data) -> None:
    """GET /stores/{store_id}/inventory/summary calculates high-level KPI cards."""
    response = live_client.get("/api/v1/stores/test-store-p3/inventory/summary")
    assert response.status_code == 200
    summary = response.json()

    assert summary["store_id"] == "test-store-p3"
    assert summary["total_products"] == 2
    assert summary["in_stock_units"] == 155.0  # 50 + 100 + 5
    assert summary["active_batches"] == 2      # 2 Dolo batches active
    assert summary["expired_batches"] == 1     # 1 Azithral batch expired
    assert summary["low_stock_items"] == 1     # Azithral (5 units <= 20)
