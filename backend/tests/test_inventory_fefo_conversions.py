"""Automated integration tests for Phase 5: Multi-Unit Conversions & FEFO Auto-Allocation Engine."""

from datetime import datetime, timedelta, timezone
import pytest
from fastapi.testclient import TestClient



# ==============================================================================
# Unit Conversion Tests
# ==============================================================================

def test_unit_conversions_standard_lookup(live_client: TestClient):
    """Test standard packaging conversions (Strip -> Tablet, Box -> Tablet, Bottle -> ML)."""
    store_id = "test-store-p5"

    # 1. Strip -> Tablet (10x)
    r1 = live_client.post(
        f"/api/v1/stores/{store_id}/inventory/conversions",
        json={"from_unit": "STRIP", "to_unit": "TABLET", "quantity": 7},
    )
    assert r1.status_code == 200, r1.text
    d1 = r1.json()
    assert d1["from_unit"] == "STRIP"
    assert d1["to_unit"] == "TABLET"
    assert d1["entered_quantity"] == 7.0
    assert d1["converted_quantity"] == 70.0
    assert d1["conversion_factor"] == 10.0
    assert "Applied standard pharmacy packaging conversion" in d1["notes"]

    # 2. Box -> Tablet (100x)
    r2 = live_client.post(
        f"/api/v1/stores/{store_id}/inventory/conversions",
        json={"from_unit": "box", "to_unit": "tablet", "quantity": 3},
    )
    assert r2.status_code == 200, r2.text
    d2 = r2.json()
    assert d2["from_unit"] == "BOX"
    assert d2["to_unit"] == "TABLET"
    assert d2["converted_quantity"] == 300.0
    assert d2["conversion_factor"] == 100.0

    # 3. Bottle -> ML (100x)
    r3 = live_client.post(
        f"/api/v1/stores/{store_id}/inventory/conversions",
        json={"from_unit": "BOTTLE", "to_unit": "ML", "quantity": 2.5},
    )
    assert r3.status_code == 200, r3.text
    d3 = r3.json()
    assert d3["converted_quantity"] == 250.0
    assert d3["conversion_factor"] == 100.0

    # 4. Identical units (1x)
    r4 = live_client.post(
        f"/api/v1/stores/{store_id}/inventory/conversions",
        json={"from_unit": "TABLET", "to_unit": "TABLET", "quantity": 42},
    )
    assert r4.status_code == 200, r4.text
    d4 = r4.json()
    assert d4["converted_quantity"] == 42.0
    assert d4["conversion_factor"] == 1.0


def test_unit_conversions_custom_factor(live_client: TestClient):
    """Test custom conversion factor override."""
    store_id = "test-store-p5"

    res = live_client.post(
        f"/api/v1/stores/{store_id}/inventory/conversions",
        json={
            "from_unit": "BLISTER_PACK",
            "to_unit": "CAPSULE",
            "quantity": 4,
            "custom_factor": 12.0,
        },
    )
    assert res.status_code == 200, res.text
    data = res.json()
    assert data["from_unit"] == "BLISTER_PACK"
    assert data["to_unit"] == "CAPSULE"
    assert data["entered_quantity"] == 4.0
    assert data["converted_quantity"] == 48.0
    assert data["conversion_factor"] == 12.0
    assert "Applied custom conversion factor" in data["notes"]


# ==============================================================================
# FEFO Simulation & Preview Tests
# ==============================================================================

def test_fefo_preview_multi_lot_ordering_and_unexpired_filtering(live_client: TestClient):
    """Test FEFO preview accurately prioritizes unexpired lots by earliest expiry date."""
    store_id = "test-store-p5"
    prod_id = "prod-fefo-test-1"
    today = datetime.now(timezone.utc).date()

    exp_expired = (today - timedelta(days=30)).isoformat()
    exp_near = (today + timedelta(days=20)).isoformat()
    exp_far = (today + timedelta(days=120)).isoformat()

    # 1. Register Batch 1 (Expired): 50 units
    r_b1 = live_client.post(
        f"/api/v1/stores/{store_id}/batches",
        json={
            "product_id": prod_id,
            "batch_number": "B-EXP-001",
            "expiry_date": exp_expired,
            "current_quantity": 50.0,
            "base_unit": "TABLET",
            "initial_quantity": 50.0,
            "mrp": 100.0,
        },
    )
    assert r_b1.status_code == 201, r_b1.text

    # 2. Register Batch 2 (Near Expiry): 30 units
    r_b2 = live_client.post(
        f"/api/v1/stores/{store_id}/batches",
        json={
            "product_id": prod_id,
            "batch_number": "B-NEAR-002",
            "expiry_date": exp_near,
            "current_quantity": 30.0,
            "base_unit": "TABLET",
            "initial_quantity": 30.0,
            "mrp": 100.0,
        },
    )
    assert r_b2.status_code == 201, r_b2.text

    # 3. Register Batch 3 (Far Expiry): 70 units
    r_b3 = live_client.post(
        f"/api/v1/stores/{store_id}/batches",
        json={
            "product_id": prod_id,
            "batch_number": "B-FAR-003",
            "expiry_date": exp_far,
            "current_quantity": 70.0,
            "base_unit": "TABLET",
            "initial_quantity": 70.0,
            "mrp": 100.0,
        },
    )
    assert r_b3.status_code == 201, r_b3.text

    # 4. Preview dispensing 4 STRIPS = 40 TABLETS (Near batch has 30, Far batch has 70)
    prev_res = live_client.post(
        f"/api/v1/stores/{store_id}/inventory/fefo-preview",
        json={
            "product_id": prod_id,
            "quantity": 4.0,
            "unit": "STRIP",
            "include_expired": False,
        },
    )
    assert prev_res.status_code == 200, prev_res.text
    prev = prev_res.json()

    assert prev["store_id"] == store_id
    assert prev["product_id"] == prod_id
    assert prev["requested_quantity"] == 4.0
    assert prev["requested_unit"] == "STRIP"
    assert prev["base_quantity_required"] == 40.0
    assert prev["total_available_unexpired"] == 100.0  # 30 (near) + 70 (far), expired excluded
    assert prev["is_fully_fulfillable"] is True
    assert prev["shortage"] == 0.0

    # Check allocation breakdown: Batch 2 first (all 30), then Batch 3 (10)
    allocs = prev["allocations"]
    assert len(allocs) == 2
    assert allocs[0]["batch_number"] == "B-NEAR-002"
    assert allocs[0]["allocated_quantity"] == 30.0
    assert allocs[0]["remaining_batch_quantity"] == 0.0

    assert allocs[1]["batch_number"] == "B-FAR-003"
    assert allocs[1]["allocated_quantity"] == 10.0
    assert allocs[1]["remaining_batch_quantity"] == 60.0


def test_fefo_preview_shortage_detection(live_client: TestClient):
    """Test FEFO preview indicates shortage when unexpired stock is insufficient."""
    store_id = "test-store-p5"
    prod_id = "prod-fefo-test-1"

    # Request 15 STRIPS = 150 TABLETS (only 100 unexpired available)
    prev_res = live_client.post(
        f"/api/v1/stores/{store_id}/inventory/fefo-preview",
        json={
            "product_id": prod_id,
            "quantity": 15.0,
            "unit": "STRIP",
            "include_expired": False,
        },
    )
    assert prev_res.status_code == 200, prev_res.text
    prev = prev_res.json()

    assert prev["base_quantity_required"] == 150.0
    assert prev["total_available_unexpired"] == 100.0
    assert prev["is_fully_fulfillable"] is False
    assert prev["shortage"] == 50.0


# ==============================================================================
# Multi-Lot FEFO Dispense & Ledger Tagging Tests
# ==============================================================================

def test_fefo_dispense_atomic_execution_and_inferred_ledger_tagging(live_client: TestClient):
    """Test POST /fefo-dispense atomically splits deduction across lots and tags ledger with is_inferred: True."""
    store_id = "test-store-p5"
    prod_id = "prod-fefo-test-1"

    # Dispense 4 STRIPS = 40 TABLETS
    disp_res = live_client.post(
        f"/api/v1/stores/{store_id}/inventory/fefo-dispense",
        json={
            "product_id": prod_id,
            "quantity": 4.0,
            "unit": "STRIP",
            "source_document": {
                "document_type": "SALES_REPORT",
                "document_id": "REC-FEFO-9001",
                "document_number": "RCP-9001",
            },
            "idempotency_key": "FEFO-DISPENSE-TX-9001",
            "actor_id": "PHARMACIST-ALICE",
            "notes": "Dispensed to outpatient",
        },
    )
    assert disp_res.status_code == 201, disp_res.text
    data = disp_res.json()

    assert data["store_id"] == store_id
    assert data["product_id"] == prod_id
    assert data["total_dispensed_base_units"] == 40.0
    assert data["entered_quantity"] == 4.0
    assert data["entered_unit"] == "STRIP"
    assert data["conversion_factor"] == 10.0

    # Verify transactions returned
    txs = data["transactions"]
    assert len(txs) == 2

    # Check first split (Batch NEAR: -30)
    assert txs[0]["batch_number"] == "B-NEAR-002"
    assert txs[0]["quantity"] == -30.0
    assert txs[0]["is_inferred"] is True
    assert txs[0]["idempotency_key"] == "FEFO-DISPENSE-TX-9001"

    # Check second split (Batch FAR: -10)
    assert txs[1]["batch_number"] == "B-FAR-003"
    assert txs[1]["quantity"] == -10.0
    assert txs[1]["is_inferred"] is True
    assert txs[1]["idempotency_key"] == "FEFO-DISPENSE-TX-9001-fefo-1"

    # Verify batch stocks in DB
    b_near = live_client.get(f"/api/v1/stores/{store_id}/batches/B-NEAR-002").json()
    assert b_near["current_quantity"] == 0.0

    b_far = live_client.get(f"/api/v1/stores/{store_id}/batches/B-FAR-003").json()
    assert b_far["current_quantity"] == 60.0  # 70 - 10 = 60


def test_fefo_dispense_idempotency_conflict(live_client: TestClient):
    """Test replaying a FEFO dispense with identical idempotency key returns HTTP 409 Conflict."""
    store_id = "test-store-p5"
    prod_id = "prod-fefo-test-1"

    res = live_client.post(
        f"/api/v1/stores/{store_id}/inventory/fefo-dispense",
        json={
            "product_id": prod_id,
            "quantity": 1.0,
            "unit": "STRIP",
            "source_document": {
                "document_type": "SALES_REPORT",
                "document_id": "REC-FEFO-9001",
            },
            "idempotency_key": "FEFO-DISPENSE-TX-9001",  # Same key
        },
    )
    assert res.status_code == 409, res.text
    err = res.json()
    assert err["detail"]["code"] == "DUPLICATE_IDEMPOTENCY_KEY"


def test_fefo_dispense_insufficient_stock_aborts_without_partial_writes(live_client: TestClient):
    """Test that requesting more stock than available aborts with HTTP 400 and zero partial deductions."""
    store_id = "test-store-p5"
    prod_id = "prod-fefo-test-1"

    # Only 60 TABLETS remain in B-FAR-003. Request 8 STRIPS = 80 TABLETS.
    res = live_client.post(
        f"/api/v1/stores/{store_id}/inventory/fefo-dispense",
        json={
            "product_id": prod_id,
            "quantity": 8.0,
            "unit": "STRIP",
            "source_document": {
                "document_type": "SALES_REPORT",
                "document_id": "REC-OVERDRAFT-1",
            },
            "idempotency_key": "FEFO-OVERDRAFT-KEY",
        },
    )
    assert res.status_code == 400, res.text
    assert res.json()["detail"]["code"] == "INSUFFICIENT_STOCK"

    # Verify B-FAR-003 stock is still 60.0 (no partial deduction)
    b_far = live_client.get(f"/api/v1/stores/{store_id}/batches/B-FAR-003").json()
    assert b_far["current_quantity"] == 60.0


def test_post_movement_automatic_fefo_fallback(live_client: TestClient):
    """Test outward stock movement without designated batch invokes automatic FEFO allocation."""
    store_id = "test-store-p5"
    prod_id = "prod-fefo-test-1"

    # Post movement with negative quantity and no batch specified
    res = live_client.post(
        f"/api/v1/stores/{store_id}/inventory/movements",
        json={
            "product_id": prod_id,
            "movement_type": "SALES_REPORT_OUT",
            "quantity": -20.0,
            "base_unit": "TABLET",
            "idempotency_key": "AUTO-FEFO-FALLBACK-TX-1",
            "source_document": {
                "document_type": "SALES_REPORT",
                "document_id": "REC-FALLBACK-1",
            },
        },
    )
    assert res.status_code == 201, res.text
    tx = res.json()

    assert tx["is_inferred"] is True
    assert tx["batch_number"] == "B-FAR-003"
    assert tx["quantity"] == -20.0

    # Stock should now be 60 - 20 = 40
    b_far = live_client.get(f"/api/v1/stores/{store_id}/batches/B-FAR-003").json()
    assert b_far["current_quantity"] == 40.0
