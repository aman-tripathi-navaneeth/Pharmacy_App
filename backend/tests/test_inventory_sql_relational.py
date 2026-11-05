"""Automated relational database test suite for Module 5 (SQL Engine Mode).

Validates end-to-end API operation against a transactional SQL engine (SQLite Async / PostgreSQL):
- Atomic stock ledger append-only logging
- Idempotency deduplication
- Negative stock overdraft prevention
- Multi-lot FEFO preview and dispense
- Audit reversal accounting
- 5-tier near-expiry monitoring & segregation
- 4-tier stockout replenishment evaluation
"""

from datetime import date, datetime, timedelta, timezone
import pytest
from fastapi.testclient import TestClient
from sqlalchemy.ext.asyncio import create_async_engine, async_sessionmaker, AsyncSession
from sqlalchemy.pool import StaticPool

from app.core.database import Base
import app.core.database as db_module
from app.main import app, settings


@pytest.fixture(scope="module")
def sql_test_client():
    """Setup TestClient backed by an in-memory async SQLite engine with StaticPool in pure SQL mode."""
    test_db_url = "sqlite+aiosqlite:///:memory:"
    engine = create_async_engine(
        test_db_url,
        echo=False,
        connect_args={"check_same_thread": False},
        poolclass=StaticPool,
    )
    session_factory = async_sessionmaker(engine, class_=AsyncSession, expire_on_commit=False)

    orig_engine = db_module._async_engine
    orig_factory = db_module._async_session_factory
    db_module._async_engine = engine
    db_module._async_session_factory = session_factory

    # Initialize relational schema
    import asyncio
    async def init_schema():
        async with engine.begin() as conn:
            await conn.run_sync(Base.metadata.create_all)

    asyncio.run(init_schema())

    with TestClient(app) as client:
        client.app.state.db_engine = engine
        yield client

    async def cleanup():
        await engine.dispose()
    asyncio.run(cleanup())

    db_module._async_engine = orig_engine
    db_module._async_session_factory = orig_factory
    app.state.db_engine = None


def test_sql_connectivity_endpoint(sql_test_client: TestClient):
    """Test GET /inventory/connectivity reports connected status in SQL mode."""
    res = sql_test_client.get("/api/v1/stores/sql-store-1/inventory/connectivity")
    assert res.status_code == 200, res.text
    data = res.json()
    assert data["status"] == "route-ready"
    assert data["database_status"] == "connected"
    assert "sqlite" in data["database"].lower()


def test_sql_batch_registration_and_fefo_sorting(sql_test_client: TestClient):
    """Test batch registration and FEFO retrieval in SQL mode."""
    store_id = "sql-store-1"
    prod_id = "PROD-PARACETAMOL-500"
    today = datetime.now(timezone.utc).date()

    # 1. Register Batch A (Far Expiry)
    r1 = sql_test_client.post(
        f"/api/v1/stores/{store_id}/batches",
        json={
            "product_id": prod_id,
            "batch_number": "PARA-FAR-001",
            "expiry_date": (today + timedelta(days=180)).isoformat(),
            "initial_quantity": 50.0,
            "mrp": 30.0,
            "purchase_rate": 18.0,
            "base_unit": "TABLET",
        },
    )
    assert r1.status_code == 201, r1.text
    b1 = r1.json()
    assert b1["batch_number"] == "PARA-FAR-001"
    assert b1["current_quantity"] == 50.0

    # 2. Register Batch B (Near Expiry)
    r2 = sql_test_client.post(
        f"/api/v1/stores/{store_id}/batches",
        json={
            "product_id": prod_id,
            "batch_number": "PARA-NEAR-002",
            "expiry_date": (today + timedelta(days=25)).isoformat(),
            "initial_quantity": 40.0,
            "mrp": 30.0,
            "purchase_rate": 18.0,
            "base_unit": "TABLET",
        },
    )
    assert r2.status_code == 201, r2.text

    # 3. Duplicate batch number rejection
    dup = sql_test_client.post(
        f"/api/v1/stores/{store_id}/batches",
        json={
            "product_id": prod_id,
            "batch_number": "PARA-NEAR-002",
            "expiry_date": (today + timedelta(days=25)).isoformat(),
            "initial_quantity": 10.0,
        },
    )
    assert dup.status_code == 409
    assert dup.json()["detail"]["code"] == "BATCH_ALREADY_EXISTS"

    # 4. Verify FEFO ordering (Near expiry first)
    b_list = sql_test_client.get(f"/api/v1/stores/{store_id}/products/{prod_id}/batches").json()
    assert len(b_list) == 2
    assert b_list[0]["batch_number"] == "PARA-NEAR-002"
    assert b_list[1]["batch_number"] == "PARA-FAR-001"


def test_sql_stock_movement_and_overdraft_prevention(sql_test_client: TestClient):
    """Test stock movements, ledger entry creation, and negative stock prevention."""
    store_id = "sql-store-1"
    prod_id = "PROD-PARACETAMOL-500"

    # Deduct 20 units from PARA-NEAR-002 (40 available)
    res = sql_test_client.post(
        f"/api/v1/stores/{store_id}/inventory/movements",
        json={
            "product_id": prod_id,
            "batch_number": "PARA-NEAR-002",
            "movement_type": "SALES_REPORT_OUT",
            "quantity": -20.0,
            "base_unit": "TABLET",
            "source_document": {
                "document_type": "SALES_REPORT",
                "document_id": "SALE-SQL-001",
                "document_number": "EOD-1",
            },
            "idempotency_key": "IDEM-SQL-OUT-001",
            "notes": "OTC counter sale",
        },
    )
    assert res.status_code == 201, res.text
    tx = res.json()
    assert tx["quantity"] == -20.0
    assert tx["movement_type"] == "SALES_REPORT_OUT"

    # Verify batch stock decreased to 20.0
    b = sql_test_client.get(f"/api/v1/stores/{store_id}/batches/PARA-NEAR-002").json()
    assert b["current_quantity"] == 20.0

    # Overdraft attempt: deduct 100 units when only 20 remain
    overdraft = sql_test_client.post(
        f"/api/v1/stores/{store_id}/inventory/movements",
        json={
            "product_id": prod_id,
            "batch_number": "PARA-NEAR-002",
            "movement_type": "SALES_REPORT_OUT",
            "quantity": -100.0,
            "base_unit": "TABLET",
            "source_document": {
                "document_type": "SALES_REPORT",
                "document_id": "SALE-OVERDRAFT",
            },
            "idempotency_key": "IDEM-SQL-OUT-OVERDRAFT",
        },
    )
    assert overdraft.status_code == 400
    assert overdraft.json()["detail"]["code"] == "INSUFFICIENT_STOCK"


def test_sql_reversal_transaction(sql_test_client: TestClient):
    """Test audit reversal creates opposite transaction and restores stock."""
    store_id = "sql-store-1"

    tx_list = sql_test_client.get(f"/api/v1/stores/{store_id}/inventory/transactions").json()["items"]
    target_tx = next(t for t in tx_list if t["idempotency_key"] == "IDEM-SQL-OUT-001")

    rev_res = sql_test_client.post(
        f"/api/v1/stores/{store_id}/inventory/movements/reversal",
        json={
            "original_transaction_id": target_tx["id"],
            "idempotency_key": "IDEM-SQL-REV-001",
            "reason": "Customer cancelled order",
        },
    )
    assert rev_res.status_code == 201, rev_res.text
    rev = rev_res.json()
    assert rev["movement_type"] == "REVERSAL"
    assert rev["quantity"] == 20.0  # Inverted from -20.0

    # Stock restored back from 20 to 40
    b = sql_test_client.get(f"/api/v1/stores/{store_id}/batches/PARA-NEAR-002").json()
    assert b["current_quantity"] == 40.0

    # Prevent double reversal
    rev_dup = sql_test_client.post(
        f"/api/v1/stores/{store_id}/inventory/movements/reversal",
        json={
            "original_transaction_id": target_tx["id"],
            "idempotency_key": "IDEM-SQL-REV-002",
            "reason": "Duplicate reversal attempt",
        },
    )
    assert rev_dup.status_code == 400
    assert rev_dup.json()["detail"]["code"] == "ALREADY_REVERSED"


def test_sql_fefo_preview_and_dispense(sql_test_client: TestClient):
    """Test FEFO auto-allocation simulation and atomic multi-batch execution."""
    store_id = "sql-store-1"
    prod_id = "PROD-PARACETAMOL-500"

    # Preview dispensing 5 STRIPS = 50 TABLETS
    # Near batch has 40, Far batch has 50
    prev_res = sql_test_client.post(
        f"/api/v1/stores/{store_id}/inventory/fefo-preview",
        json={
            "product_id": prod_id,
            "quantity": 5.0,
            "unit": "STRIP",
        },
    )
    assert prev_res.status_code == 200, prev_res.text
    prev = prev_res.json()
    assert prev["base_quantity_required"] == 50.0
    assert prev["is_fully_fulfillable"] is True
    assert len(prev["allocations"]) == 2
    assert prev["allocations"][0]["batch_number"] == "PARA-NEAR-002"
    assert prev["allocations"][0]["allocated_quantity"] == 40.0
    assert prev["allocations"][1]["batch_number"] == "PARA-FAR-001"
    assert prev["allocations"][1]["allocated_quantity"] == 10.0

    # Execute dispense
    disp_res = sql_test_client.post(
        f"/api/v1/stores/{store_id}/inventory/fefo-dispense",
        json={
            "product_id": prod_id,
            "quantity": 5.0,
            "unit": "STRIP",
            "source_document": {
                "document_type": "SALES_REPORT",
                "document_id": "DISP-SQL-001",
                "document_number": "POS-5512",
            },
            "idempotency_key": "IDEM-SQL-DISP-001",
        },
    )
    assert disp_res.status_code == 201, disp_res.text
    disp = disp_res.json()
    assert disp["total_dispensed_base_units"] == 50.0
    assert len(disp["transactions"]) == 2
    assert disp["transactions"][0]["is_inferred"] is True

    # Near batch depleted to 0, Far batch reduced from 50 to 40
    b_near = sql_test_client.get(f"/api/v1/stores/{store_id}/batches/PARA-NEAR-002").json()
    assert b_near["current_quantity"] == 0.0

    b_far = sql_test_client.get(f"/api/v1/stores/{store_id}/batches/PARA-FAR-001").json()
    assert b_far["current_quantity"] == 40.0


def test_sql_expiry_buckets_and_segregation(sql_test_client: TestClient):
    """Test near-expiry 5-tier classification and quarantine segregation."""
    store_id = "sql-store-1"
    today = datetime.now(timezone.utc).date()

    # Register an expired batch
    sql_test_client.post(
        f"/api/v1/stores/{store_id}/batches",
        json={
            "product_id": "PROD-EXPIRED-TEST",
            "batch_number": "EXP-LOT-99",
            "expiry_date": (today - timedelta(days=5)).isoformat(),
            "initial_quantity": 25.0,
            "mrp": 50.0,
            "purchase_rate": 30.0,
            "base_unit": "TABLET",
        },
    )

    # Fetch buckets
    buckets_res = sql_test_client.get(f"/api/v1/stores/{store_id}/inventory/expiry-buckets")
    assert buckets_res.status_code == 200
    buckets = buckets_res.json()
    assert len(buckets["buckets"]) == 5

    # Segregate expired lot
    seg_res = sql_test_client.post(
        f"/api/v1/stores/{store_id}/batches/EXP-LOT-99/segregate-expired",
        json={
            "quantity": 25.0,
            "reason": "Expired stock disposed",
            "idempotency_key": "IDEM-SQL-SEG-001",
        },
    )
    assert seg_res.status_code == 201, seg_res.text
    seg_tx = seg_res.json()
    assert seg_tx["movement_type"] == "ADJUSTMENT_SUBTRACT"
    assert seg_tx["quantity"] == -25.0

    # Stock is now 0
    b_exp = sql_test_client.get(f"/api/v1/stores/{store_id}/batches/EXP-LOT-99").json()
    assert b_exp["current_quantity"] == 0.0


def test_sql_low_stock_alerts_and_thresholds(sql_test_client: TestClient):
    """Test reorder thresholds configuration and low stock alert generation."""
    store_id = "sql-store-1"
    prod_id = "PROD-THRESH-TEST"

    # Set threshold
    set_thresh = sql_test_client.post(
        f"/api/v1/stores/{store_id}/inventory/thresholds/{prod_id}",
        json={
            "reorder_point": 60.0,
            "safety_stock_level": 25.0,
            "reorder_quantity": 120.0,
            "lead_time_days": 3,
        },
    )
    assert set_thresh.status_code == 200, set_thresh.text
    cfg = set_thresh.json()
    assert cfg["reorder_point"] == 60.0
    assert cfg["safety_stock_level"] == 25.0

    # Fetch alert - product has 0 stock so should be OUT_OF_STOCK
    alerts_res = sql_test_client.get(f"/api/v1/stores/{store_id}/inventory/low-stock-alerts")
    assert alerts_res.status_code == 200
    alerts = alerts_res.json()
    item = next(a for a in alerts["alerts"] if a["product_id"] == prod_id)
    assert item["severity"] == "OUT_OF_STOCK"
    assert item["suggested_reorder_quantity"] >= 120.0
