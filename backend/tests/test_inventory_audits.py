"""Automated backend test suite for Phase 8: Physical Stock Audits, Cycle Counts & Discrepancies.

Validates:
- Full Store Audits and Scope-Filtered Cycle Counts
- Blind count sheets (system quantity masking)
- Discrepancy math (surplus, shortage, zero-variance)
- Discovered unrecorded lots during physical audit
- Discrepancy financial valuation reports
- Manager approval reconciliation and atomic immutable ledger posting (ADJUSTMENT_ADD / ADJUSTMENT_SUBTRACT)
- Idempotency deduplication and closed session guardrails
- Store isolation and cancellation workflows
"""

import asyncio
from datetime import date, datetime, timedelta, timezone
import uuid
import pytest
from fastapi.testclient import TestClient

from app.core.database import get_session_factory
from app.modules.inventory_batches_stock_ledger.models import (
    AuditSessionTable,
    AuditCountItemTable,
    BatchTable,
    MovementType,
    SourceDocumentType,
    StockBalanceTable,
    StockTransactionTable,
)


@pytest.fixture(scope="module")
def seed_audit_test_data(live_client: TestClient):
    """Seed test batches and initial stock balances for audit testing."""
    session_factory = get_session_factory()
    store_id = "store-audit-p8"
    other_store = "store-audit-other"
    today = datetime.now(timezone.utc).date()

    async def _seed():
        async with session_factory() as session:
            # Batch 1: Para 500mg, 100 units @ 5.0 INR
            b1 = BatchTable(
                id="BAT-AUD-P8-1",
                store_id=store_id,
                product_id="prod-para-500",
                batch_number="PARA-LOT-100",
                expiry_date=today + timedelta(days=180),
                mrp=8.0,
                purchase_rate=5.0,
                current_quantity=100.0,
                base_unit="TABLET",
                is_active=True,
                created_at=datetime.now(timezone.utc),
                updated_at=datetime.now(timezone.utc),
            )
            # Batch 2: Amox 250mg, 50 units @ 12.0 INR
            b2 = BatchTable(
                id="BAT-AUD-P8-2",
                store_id=store_id,
                product_id="prod-amox-250",
                batch_number="AMOX-LOT-050",
                expiry_date=today + timedelta(days=365),
                mrp=18.0,
                purchase_rate=12.0,
                current_quantity=50.0,
                base_unit="TABLET",
                is_active=True,
                created_at=datetime.now(timezone.utc),
                updated_at=datetime.now(timezone.utc),
            )
            # Batch 3: Other store batch
            b3 = BatchTable(
                id="BAT-AUD-OTHER",
                store_id=other_store,
                product_id="prod-para-500",
                batch_number="PARA-OTHER-LOT",
                expiry_date=today + timedelta(days=90),
                mrp=8.0,
                purchase_rate=5.0,
                current_quantity=30.0,
                base_unit="TABLET",
                is_active=True,
                created_at=datetime.now(timezone.utc),
                updated_at=datetime.now(timezone.utc),
            )
            session.add_all([b1, b2, b3])

            bal1 = StockBalanceTable(
                id="BAL-AUD-P8-1",
                store_id=store_id,
                product_id="prod-para-500",
                batch_number="PARA-LOT-100",
                current_quantity=100.0,
                base_unit="TABLET",
                updated_at=datetime.now(timezone.utc),
            )
            bal2 = StockBalanceTable(
                id="BAL-AUD-P8-2",
                store_id=store_id,
                product_id="prod-amox-250",
                batch_number="AMOX-LOT-050",
                current_quantity=50.0,
                base_unit="TABLET",
                updated_at=datetime.now(timezone.utc),
            )
            session.add_all([bal1, bal2])
            await session.commit()

    asyncio.run(_seed())
    return {"store_id": store_id, "other_store": other_store}


def test_create_audit_session_full_and_cycle(live_client: TestClient, seed_audit_test_data):
    """Test creating full audit vs. targeted cycle count with snapshot expected items."""
    store_id = seed_audit_test_data["store_id"]

    # 1. Full Audit
    full_payload = {
        "title": "Annual Full Store Audit 2026",
        "audit_type": "FULL_AUDIT",
        "notes": "Store-wide physical verification",
        "assigned_to": "AUDITOR-01",
        "created_by": "MGR-01",
    }
    res_full = live_client.post(f"/api/v1/stores/{store_id}/inventory/audits", json=full_payload)
    assert res_full.status_code == 201
    full_data = res_full.json()
    assert full_data["id"].startswith("AUD-")
    assert full_data["status"] == "IN_PROGRESS"
    assert full_data["audit_type"] == "FULL_AUDIT"
    assert full_data["total_items_expected"] >= 2  # Both seeded batches
    assert full_data["total_items_counted"] == 0

    # 2. Cycle Count targeted to prod-amox-250
    cycle_payload = {
        "title": "Amoxicillin Cycle Count",
        "audit_type": "CYCLE_COUNT",
        "scope_product_ids": ["prod-amox-250"],
        "assigned_to": "AUDITOR-02",
        "created_by": "MGR-01",
    }
    res_cycle = live_client.post(f"/api/v1/stores/{store_id}/inventory/audits", json=cycle_payload)
    assert res_cycle.status_code == 201
    cycle_data = res_cycle.json()
    assert cycle_data["audit_type"] == "CYCLE_COUNT"
    assert cycle_data["scope_product_ids"] == ["prod-amox-250"]
    assert cycle_data["total_items_expected"] == 1


def test_list_audit_sessions_filters(live_client: TestClient, seed_audit_test_data):
    """Test listing audit sessions with query filtering."""
    store_id = seed_audit_test_data["store_id"]

    res = live_client.get(f"/api/v1/stores/{store_id}/inventory/audits?audit_type=CYCLE_COUNT")
    assert res.status_code == 200
    audits = res.json()
    assert len(audits) >= 1
    assert all(a["audit_type"] == "CYCLE_COUNT" for a in audits)


def test_blind_count_sheet_masking(live_client: TestClient, seed_audit_test_data):
    """Test that blind=True hides system expected quantities to eliminate counter confirmation bias."""
    store_id = seed_audit_test_data["store_id"]

    # Create audit session
    create_res = live_client.post(
        f"/api/v1/stores/{store_id}/inventory/audits",
        json={"title": "Blind Audit Test", "audit_type": "CYCLE_COUNT", "scope_product_ids": ["prod-para-500"]},
    )
    audit_id = create_res.json()["id"]

    # Record a count
    live_client.post(
        f"/api/v1/stores/{store_id}/inventory/audits/{audit_id}/counts",
        json={
            "items": [
                {
                    "product_id": "prod-para-500",
                    "batch_number": "PARA-LOT-100",
                    "counted_quantity": 95.0,
                    "counted_by": "STAFF-01",
                }
            ]
        },
    )

    # 1. Blind retrieval: expected quantities must be None
    res_blind = live_client.get(f"/api/v1/stores/{store_id}/inventory/audits/{audit_id}?blind=true")
    assert res_blind.status_code == 200
    blind_item = res_blind.json()["items"][0]
    assert blind_item["system_quantity"] is None
    assert blind_item["discrepancy_quantity"] is None
    assert blind_item["discrepancy_value"] is None
    assert blind_item["counted_quantity"] == 95.0

    # 2. Non-blind retrieval: expected quantities revealed
    res_open = live_client.get(f"/api/v1/stores/{store_id}/inventory/audits/{audit_id}?blind=false")
    assert res_open.status_code == 200
    open_item = res_open.json()["items"][0]
    assert open_item["system_quantity"] == 100.0
    assert open_item["discrepancy_quantity"] == -5.0
    assert open_item["discrepancy_value"] == -25.0  # -5 * 5.0 unit cost


def test_record_counts_and_discrepancy_math(live_client: TestClient, seed_audit_test_data):
    """Test submitting multiple counts: surplus, shortage, and clean match."""
    store_id = seed_audit_test_data["store_id"]

    init_res = live_client.post(
        f"/api/v1/stores/{store_id}/inventory/audits",
        json={"title": "Variance Math Audit", "audit_type": "FULL_AUDIT"},
    )
    audit_id = init_res.json()["id"]

    # Submit batch counts:
    # 1. PARA-LOT-100 (system=100): count 110 (+10 surplus @ 5.0 = +50.0)
    # 2. AMOX-LOT-050 (system=50): count 45 (-5 shortage @ 12.0 = -60.0)
    payload = {
        "items": [
            {
                "product_id": "prod-para-500",
                "product_name": "Paracetamol 500mg",
                "batch_number": "PARA-LOT-100",
                "counted_quantity": 110.0,
                "discrepancy_reason": "SURPLUS_FOUND",
                "notes": "Extra box found in shelf back",
            },
            {
                "product_id": "prod-amox-250",
                "product_name": "Amoxicillin 250mg",
                "batch_number": "AMOX-LOT-050",
                "counted_quantity": 45.0,
                "discrepancy_reason": "DAMAGE",
                "notes": "5 vials broken",
            },
        ]
    }
    counts_res = live_client.post(f"/api/v1/stores/{store_id}/inventory/audits/{audit_id}/counts", json=payload)
    assert counts_res.status_code == 200
    audit_data = counts_res.json()

    assert audit_data["status"] == "UNDER_REVIEW"
    assert audit_data["total_items_counted"] == 2
    assert audit_data["surplus_count"] == 1
    assert audit_data["shortage_count"] == 1
    assert audit_data["discrepancy_count"] == 2
    # net variance: +50.0 (surplus) - 60.0 (shortage) = -10.0
    assert audit_data["net_variance_value"] == -10.0


def test_discover_unrecorded_batch_during_count(live_client: TestClient, seed_audit_test_data):
    """Test discovering an unrecorded batch lot during physical count."""
    store_id = seed_audit_test_data["store_id"]

    init_res = live_client.post(
        f"/api/v1/stores/{store_id}/inventory/audits",
        json={"title": "Unrecorded Lot Audit", "audit_type": "CYCLE_COUNT"},
    )
    audit_id = init_res.json()["id"]

    new_lot = f"UNRECORDED-LOT-{uuid.uuid4().hex[:6].upper()}"
    payload = {
        "items": [
            {
                "product_id": "prod-para-500",
                "batch_number": new_lot,
                "counted_quantity": 25.0,
                "discrepancy_reason": "SURPLUS_FOUND",
                "notes": "Found lot not registered in system",
            }
        ]
    }
    res = live_client.post(f"/api/v1/stores/{store_id}/inventory/audits/{audit_id}/counts", json=payload)
    assert res.status_code == 200
    item = res.json()["items"][0]

    assert item["batch_number"] == new_lot
    assert item["system_quantity"] == 0.0
    assert item["counted_quantity"] == 25.0
    assert item["discrepancy_quantity"] == 25.0
    assert item["discrepancy_reason"] == "SURPLUS_FOUND"


def test_discrepancy_report_financial_valuation(live_client: TestClient, seed_audit_test_data):
    """Test discrepancy valuation breakdown report."""
    store_id = seed_audit_test_data["store_id"]

    init_res = live_client.post(
        f"/api/v1/stores/{store_id}/inventory/audits",
        json={"title": "Discrepancy Report Audit", "audit_type": "FULL_AUDIT"},
    )
    audit_id = init_res.json()["id"]

    # 1. PARA-LOT-100: system 100, counted 100 (Clean)
    # 2. AMOX-LOT-050: system 50, counted 40 (Shortage of 10 @ 12 = 120.0 deficit)
    live_client.post(
        f"/api/v1/stores/{store_id}/inventory/audits/{audit_id}/counts",
        json={
            "items": [
                {
                    "product_id": "prod-para-500",
                    "batch_number": "PARA-LOT-100",
                    "counted_quantity": 100.0,
                },
                {
                    "product_id": "prod-amox-250",
                    "batch_number": "AMOX-LOT-050",
                    "counted_quantity": 40.0,
                    "discrepancy_reason": "THEFT_SHRINKAGE",
                },
            ]
        },
    )

    report_res = live_client.get(f"/api/v1/stores/{store_id}/inventory/audits/{audit_id}/discrepancies")
    assert report_res.status_code == 200
    report = report_res.json()

    assert report["total_counted"] == 2
    assert report["total_discrepant"] == 1
    assert report["clean_items_count"] == 1
    assert report["total_shortage_value"] == 120.0
    assert report["total_surplus_value"] == 0.0
    assert report["net_variance_value"] == -120.0
    assert len(report["discrepant_items"]) == 1
    assert report["discrepant_items"][0]["batch_number"] == "AMOX-LOT-050"


def test_reconcile_audit_session_and_ledger_posting(live_client: TestClient, seed_audit_test_data):
    """Test reconciliation: atomic adjustment posting to stock ledger & stock update."""
    store_id = seed_audit_test_data["store_id"]

    init_res = live_client.post(
        f"/api/v1/stores/{store_id}/inventory/audits",
        json={"title": "Reconciliation Audit", "audit_type": "FULL_AUDIT"},
    )
    audit_id = init_res.json()["id"]

    # Record shortage of 8 units on AMOX-LOT-050 (system 50 -> counted 42)
    live_client.post(
        f"/api/v1/stores/{store_id}/inventory/audits/{audit_id}/counts",
        json={
            "items": [
                {
                    "product_id": "prod-amox-250",
                    "batch_number": "AMOX-LOT-050",
                    "counted_quantity": 42.0,
                    "discrepancy_reason": "DAMAGE",
                }
            ]
        },
    )

    # Reconcile audit
    idem_key = f"IDEM-RECON-{uuid.uuid4().hex[:8]}"
    recon_payload = {
        "approved_by": "CHIEF-PHARMACIST-01",
        "idempotency_key": idem_key,
        "notes": "Monthly write-off verified",
    }
    recon_res = live_client.post(f"/api/v1/stores/{store_id}/inventory/audits/{audit_id}/reconcile", json=recon_payload)
    assert recon_res.status_code == 200
    recon_data = recon_res.json()

    assert recon_data["status"] == "RECONCILED"
    assert recon_data["approved_by"] == "CHIEF-PHARMACIST-01"
    assert recon_data["reconciled_items_count"] == 1
    assert recon_data["ledger_transactions_posted"] == 1
    assert recon_data["total_shortage_qty"] == 8.0
    assert recon_data["net_financial_adjustment"] == -96.0  # -8 * 12.0

    # Verify audit session status is updated
    audit_check = live_client.get(f"/api/v1/stores/{store_id}/inventory/audits/{audit_id}")
    assert audit_check.json()["status"] == "RECONCILED"
    assert audit_check.json()["approved_by"] == "CHIEF-PHARMACIST-01"

    # Verify ledger transaction exists in stock transactions
    tx_res = live_client.get(f"/api/v1/stores/{store_id}/inventory/transactions?product_id=prod-amox-250")
    assert tx_res.status_code == 200
    txs = tx_res.json()["items"]
    audit_tx = next((t for t in txs if t["movement_type"] == "ADJUSTMENT_SUBTRACT"), None)
    assert audit_tx is not None
    assert audit_tx["quantity"] == -8.0
    assert audit_tx["source_document"]["document_type"] == "STOCK_AUDIT"
    assert audit_tx["source_document"]["document_id"] == audit_id

    # Verify batch stock is now 42.0
    batches_res = live_client.get(f"/api/v1/stores/{store_id}/products/prod-amox-250/batches")
    assert batches_res.status_code == 200
    amox_batch = next(b for b in batches_res.json() if b["batch_number"] == "AMOX-LOT-050")
    assert amox_batch["current_quantity"] == 42.0


def test_reconcile_idempotency_and_guardrails(live_client: TestClient, seed_audit_test_data):
    """Test duplicate idempotency key rejection and closed audit safeguards."""
    store_id = seed_audit_test_data["store_id"]

    init_res = live_client.post(
        f"/api/v1/stores/{store_id}/inventory/audits",
        json={"title": "Guardrails Audit", "audit_type": "CYCLE_COUNT"},
    )
    audit_id = init_res.json()["id"]

    live_client.post(
        f"/api/v1/stores/{store_id}/inventory/audits/{audit_id}/counts",
        json={
            "items": [
                {
                    "product_id": "prod-para-500",
                    "batch_number": "PARA-LOT-100",
                    "counted_quantity": 90.0,
                }
            ]
        },
    )

    idem_key = f"IDEM-GUARD-{uuid.uuid4().hex[:8]}"
    recon_payload = {"approved_by": "MGR-01", "idempotency_key": idem_key}

    # 1. First reconciliation succeeds
    res1 = live_client.post(f"/api/v1/stores/{store_id}/inventory/audits/{audit_id}/reconcile", json=recon_payload)
    assert res1.status_code == 200

    # 2. Duplicate idempotency key triggers 409 Conflict
    res2 = live_client.post(f"/api/v1/stores/{store_id}/inventory/audits/{audit_id}/reconcile", json=recon_payload)
    assert res2.status_code in (400, 409)

    # 3. Cannot submit counts to already reconciled audit
    res3 = live_client.post(
        f"/api/v1/stores/{store_id}/inventory/audits/{audit_id}/counts",
        json={"items": [{"product_id": "prod-para-500", "batch_number": "PARA-LOT-100", "counted_quantity": 80.0}]},
    )
    assert res3.status_code == 400
    assert res3.json()["detail"]["code"] == "AUDIT_CLOSED"


def test_cancel_audit_session(live_client: TestClient, seed_audit_test_data):
    """Test cancelling an in-progress audit and protecting reconciled audits from cancellation."""
    store_id = seed_audit_test_data["store_id"]

    # 1. Cancel in-progress audit
    init_res = live_client.post(
        f"/api/v1/stores/{store_id}/inventory/audits",
        json={"title": "To Be Cancelled", "audit_type": "FULL_AUDIT"},
    )
    audit_id = init_res.json()["id"]

    cancel_res = live_client.post(f"/api/v1/stores/{store_id}/inventory/audits/{audit_id}/cancel?reason=Shift%20Ended")
    assert cancel_res.status_code == 200
    assert cancel_res.json()["status"] == "CANCELLED"

    # Cannot reconcile a cancelled audit
    recon_res = live_client.post(
        f"/api/v1/stores/{store_id}/inventory/audits/{audit_id}/reconcile",
        json={"approved_by": "MGR-01", "idempotency_key": f"IDEM-CANC-{uuid.uuid4().hex[:6]}"},
    )
    assert recon_res.status_code == 400
    assert recon_res.json()["detail"]["code"] == "AUDIT_CANCELLED"


def test_store_isolation_on_audits(live_client: TestClient, seed_audit_test_data):
    """Test that audits are strictly store-isolated."""
    store_id = seed_audit_test_data["store_id"]
    other_store = seed_audit_test_data["other_store"]

    init_res = live_client.post(
        f"/api/v1/stores/{store_id}/inventory/audits",
        json={"title": "Isolated Audit", "audit_type": "CYCLE_COUNT"},
    )
    audit_id = init_res.json()["id"]

    # Attempt to view audit from other store
    res_other = live_client.get(f"/api/v1/stores/{other_store}/inventory/audits/{audit_id}")
    assert res_other.status_code == 404
    assert res_other.json()["detail"]["code"] == "AUDIT_NOT_FOUND"
