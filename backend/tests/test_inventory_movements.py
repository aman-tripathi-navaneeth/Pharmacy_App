"""Automated integration tests for Phase 4: Stock Ledger & Stock Movement Logic."""

from datetime import datetime, timedelta, timezone
import pytest
from fastapi.testclient import TestClient



def test_register_batch_with_initial_stock(live_client: TestClient):
    """Test POST /batches registers a lot and writes initial inward transaction to ledger."""
    store_id = "test-store-p4"
    expiry = (datetime.now(timezone.utc).date() + timedelta(days=365)).isoformat()

    payload = {
        "product_id": "prod-amox-500",
        "batch_number": "amx-2026-a1",  # will be auto-capitalized
        "expiry_date": expiry,
        "mrp": 120.0,
        "purchase_rate": 80.0,
        "initial_quantity": 100.0,
        "base_unit": "capsule",
    }

    res = live_client.post(f"/api/v1/stores/{store_id}/batches", json=payload)
    assert res.status_code == 201, res.text
    data = res.json()
    assert data["batch_number"] == "AMX-2026-A1"
    assert data["base_unit"] == "CAPSULE"
    assert data["current_quantity"] == 100.0
    assert data["store_id"] == store_id

    # Verify initial inward transaction was automatically recorded in stock ledger
    tx_res = live_client.get(f"/api/v1/stores/{store_id}/inventory/transactions")
    assert tx_res.status_code == 200
    tx_data = tx_res.json()
    assert tx_data["total"] >= 1
    init_tx = tx_data["items"][0]
    assert init_tx["movement_type"] == "PURCHASE_IN"
    assert init_tx["quantity"] == 100.0
    assert init_tx["batch_number"] == "AMX-2026-A1"


def test_register_duplicate_batch_rejected(live_client: TestClient):
    """Test unique constraint: duplicate (store_id, product_id, batch_number) returns 409."""
    store_id = "test-store-p4"
    expiry = (datetime.now(timezone.utc).date() + timedelta(days=365)).isoformat()

    payload = {
        "product_id": "prod-amox-500",
        "batch_number": "AMX-2026-A1",
        "expiry_date": expiry,
        "mrp": 120.0,
        "purchase_rate": 80.0,
        "initial_quantity": 50.0,
        "base_unit": "CAPSULE",
    }

    res = live_client.post(f"/api/v1/stores/{store_id}/batches", json=payload)
    assert res.status_code == 409
    assert res.json()["detail"]["code"] == "BATCH_ALREADY_EXISTS"


def test_post_stock_movement_inward(live_client: TestClient):
    """Test POST /inventory/movements with PURCHASE_IN increments batch stock and updates ledger."""
    store_id = "test-store-p4"

    movement = {
        "product_id": "prod-amox-500",
        "batch_number": "AMX-2026-A1",
        "movement_type": "PURCHASE_IN",
        "quantity": 50.0,
        "base_unit": "CAPSULE",
        "source_document": {
            "document_type": "PURCHASE_INVOICE",
            "document_id": "INV-P4-001",
            "document_number": "INV/2026/P4",
        },
        "idempotency_key": "IDEM-P4-IN-001",
        "notes": "Supplemental inward order",
    }

    res = live_client.post(f"/api/v1/stores/{store_id}/inventory/movements", json=movement)
    assert res.status_code == 201, res.text
    tx = res.json()
    assert tx["movement_type"] == "PURCHASE_IN"
    assert tx["quantity"] == 50.0

    # Verify batch quantity updated to 150 (100 + 50)
    batch_res = live_client.get(f"/api/v1/stores/{store_id}/batches/AMX-2026-A1")
    assert batch_res.status_code == 200
    assert batch_res.json()["current_quantity"] == 150.0


def test_post_stock_movement_outward_sales(live_client: TestClient):
    """Test POST /inventory/movements with SALES_REPORT_OUT decrements batch stock."""
    store_id = "test-store-p4"

    movement = {
        "product_id": "prod-amox-500",
        "batch_number": "AMX-2026-A1",
        "movement_type": "SALES_REPORT_OUT",
        "quantity": -30.0,
        "base_unit": "CAPSULE",
        "source_document": {
            "document_type": "SALES_REPORT",
            "document_id": "SALES-P4-001",
            "document_number": "EOD-OCT-19",
        },
        "idempotency_key": "IDEM-P4-OUT-001",
        "notes": "EOD sales register deduction",
    }

    res = live_client.post(f"/api/v1/stores/{store_id}/inventory/movements", json=movement)
    assert res.status_code == 201, res.text
    tx = res.json()
    assert tx["movement_type"] == "SALES_REPORT_OUT"
    assert tx["quantity"] == -30.0

    # Verify batch quantity decremented to 120 (150 - 30)
    batch_res = live_client.get(f"/api/v1/stores/{store_id}/batches/AMX-2026-A1")
    assert batch_res.status_code == 200
    assert batch_res.json()["current_quantity"] == 120.0


def test_negative_stock_prevention(live_client: TestClient):
    """Test that outward movement exceeding available stock is rejected with 400 Bad Request."""
    store_id = "test-store-p4"

    # Attempt to deduct 500 units when only 120 available
    movement = {
        "product_id": "prod-amox-500",
        "batch_number": "AMX-2026-A1",
        "movement_type": "SALES_REPORT_OUT",
        "quantity": -500.0,
        "base_unit": "CAPSULE",
        "source_document": {
            "document_type": "SALES_REPORT",
            "document_id": "SALES-OVERDRAFT",
            "document_number": "OVERDRAFT",
        },
        "idempotency_key": "IDEM-P4-OUT-OVERDRAFT",
    }

    res = live_client.post(f"/api/v1/stores/{store_id}/inventory/movements", json=movement)
    assert res.status_code == 400
    err = res.json()
    assert err["detail"]["code"] == "INSUFFICIENT_STOCK"

    # Verify batch quantity remains unchanged at 120.0
    batch_res = live_client.get(f"/api/v1/stores/{store_id}/batches/AMX-2026-A1")
    assert batch_res.json()["current_quantity"] == 120.0


def test_idempotency_key_deduplication(live_client: TestClient):
    """Test that duplicate idempotency keys return 409 Conflict without double deducting stock."""
    store_id = "test-store-p4"

    movement = {
        "product_id": "prod-amox-500",
        "batch_number": "AMX-2026-A1",
        "movement_type": "SALES_REPORT_OUT",
        "quantity": -10.0,
        "base_unit": "CAPSULE",
        "source_document": {
            "document_type": "SALES_REPORT",
            "document_id": "SALES-RETRY",
        },
        "idempotency_key": "IDEM-P4-OUT-001",  # Already used in earlier test
    }

    res = live_client.post(f"/api/v1/stores/{store_id}/inventory/movements", json=movement)
    assert res.status_code == 409
    assert res.json()["detail"]["code"] == "DUPLICATE_IDEMPOTENCY_KEY"


def test_reverse_stock_transaction(live_client: TestClient):
    """Test POST /inventory/movements/reversal creates an opposite transaction and updates stock."""
    store_id = "test-store-p4"

    # Locate the sales transaction that deducted -30
    tx_list = live_client.get(f"/api/v1/stores/{store_id}/inventory/transactions").json()["items"]
    target_tx = next(t for t in tx_list if t["idempotency_key"] == "IDEM-P4-OUT-001")
    target_id = target_tx["id"]

    reversal_payload = {
        "original_transaction_id": target_id,
        "idempotency_key": "IDEM-P4-REV-001",
        "reason": "Customer cancelled sales order; stock returned to batch",
    }

    res = live_client.post(f"/api/v1/stores/{store_id}/inventory/movements/reversal", json=reversal_payload)
    assert res.status_code == 201, res.text
    rev = res.json()
    assert rev["movement_type"] == "REVERSAL"
    assert rev["quantity"] == 30.0  # Opposite of original -30.0

    # Verify batch stock restored from 120.0 back to 150.0
    batch_res = live_client.get(f"/api/v1/stores/{store_id}/batches/AMX-2026-A1")
    assert batch_res.json()["current_quantity"] == 150.0

    # Verify original transaction was preserved and never deleted
    orig_check = live_client.get(f"/api/v1/stores/{store_id}/inventory/transactions").json()["items"]
    assert any(t["id"] == target_id for t in orig_check)


def test_reversal_rejected_if_already_reversed(live_client: TestClient):
    """Test that attempting to reverse an already reversed transaction returns 400 Bad Request."""
    store_id = "test-store-p4"

    tx_list = live_client.get(f"/api/v1/stores/{store_id}/inventory/transactions").json()["items"]
    target_tx = next(t for t in tx_list if t["idempotency_key"] == "IDEM-P4-OUT-001")

    payload = {
        "original_transaction_id": target_tx["id"],
        "idempotency_key": "IDEM-P4-REV-002",
        "reason": "Duplicate reversal attempt",
    }

    res = live_client.post(f"/api/v1/stores/{store_id}/inventory/movements/reversal", json=payload)
    assert res.status_code == 400
    assert res.json()["detail"]["code"] == "ALREADY_REVERSED"


def test_store_isolation_on_write(live_client: TestClient):
    """Test cross-store write prevention: store B cannot mutate batch of store A."""
    # other-store-p4 tries to mutate AMX-2026-A1 which belongs to test-store-p4
    movement = {
        "product_id": "prod-amox-500",
        "batch_number": "AMX-2026-A1",
        "movement_type": "SALES_REPORT_OUT",
        "quantity": -5.0,
        "base_unit": "CAPSULE",
        "source_document": {
            "document_type": "SALES_REPORT",
            "document_id": "DOC-XSTORE",
        },
        "idempotency_key": "IDEM-XSTORE-001",
    }

    res = live_client.post("/api/v1/stores/other-store-p4/inventory/movements", json=movement)
    assert res.status_code == 404
    assert res.json()["detail"]["code"] == "BATCH_NOT_FOUND"
