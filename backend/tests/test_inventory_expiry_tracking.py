"""Automated integration tests for Phase 6: Expiry Date Tracking, Near-Expiry Alerts & Waste Minimization."""

from datetime import datetime, timedelta, timezone
import pytest
from fastapi.testclient import TestClient



# ==============================================================================
# Expiry Buckets & At-Risk Valuation Tests
# ==============================================================================

def test_expiry_buckets_multi_tier_classification_and_valuation(live_client: TestClient):
    """Test multi-tier expiry classification across 5 tiers with at-risk capital valuation."""
    store_id = "test-store-p6"
    prod_id = "prod-expiry-test"
    today = datetime.now(timezone.utc).date()

    # 1. Register Batch 1 (EXPIRED): -10 days, qty: 20, purchase: 10, mrp: 15
    live_client.post(
        f"/api/v1/stores/{store_id}/batches",
        json={
            "product_id": prod_id,
            "batch_number": "B-EXP-01",
            "expiry_date": (today - timedelta(days=10)).isoformat(),
            "current_quantity": 20.0,
            "base_unit": "TABLET",
            "initial_quantity": 20.0,
            "purchase_rate": 10.0,
            "mrp": 15.0,
        },
    )

    # 2. Register Batch 2 (CRITICAL_30): +15 days, qty: 30, purchase: 20, mrp: 30
    live_client.post(
        f"/api/v1/stores/{store_id}/batches",
        json={
            "product_id": prod_id,
            "batch_number": "B-CRIT-02",
            "expiry_date": (today + timedelta(days=15)).isoformat(),
            "current_quantity": 30.0,
            "base_unit": "TABLET",
            "initial_quantity": 30.0,
            "purchase_rate": 20.0,
            "mrp": 30.0,
        },
    )

    # 3. Register Batch 3 (NEAR_60): +45 days, qty: 40, purchase: 25, mrp: 40
    live_client.post(
        f"/api/v1/stores/{store_id}/batches",
        json={
            "product_id": prod_id,
            "batch_number": "B-NEAR-03",
            "expiry_date": (today + timedelta(days=45)).isoformat(),
            "current_quantity": 40.0,
            "base_unit": "TABLET",
            "initial_quantity": 40.0,
            "purchase_rate": 25.0,
            "mrp": 40.0,
        },
    )

    # 4. Register Batch 4 (ATTENTION_90): +75 days, qty: 50, purchase: 30, mrp: 50
    live_client.post(
        f"/api/v1/stores/{store_id}/batches",
        json={
            "product_id": prod_id,
            "batch_number": "B-ATTN-04",
            "expiry_date": (today + timedelta(days=75)).isoformat(),
            "current_quantity": 50.0,
            "base_unit": "TABLET",
            "initial_quantity": 50.0,
            "purchase_rate": 30.0,
            "mrp": 50.0,
        },
    )

    # 5. Register Batch 5 (SAFE): +200 days, qty: 100, purchase: 50, mrp: 80
    live_client.post(
        f"/api/v1/stores/{store_id}/batches",
        json={
            "product_id": prod_id,
            "batch_number": "B-SAFE-05",
            "expiry_date": (today + timedelta(days=200)).isoformat(),
            "current_quantity": 100.0,
            "base_unit": "TABLET",
            "initial_quantity": 100.0,
            "purchase_rate": 50.0,
            "mrp": 80.0,
        },
    )

    # Fetch Expiry Buckets
    res = live_client.get(f"/api/v1/stores/{store_id}/inventory/expiry-buckets")
    assert res.status_code == 200, res.text
    data = res.json()

    assert data["store_id"] == store_id
    assert data["total_active_batches"] == 5

    # At-risk units (non-safe stock: 20 + 30 + 40 + 50 = 140)
    assert data["total_at_risk_units"] == 140.0

    # At-risk purchase value: 20*10 + 30*20 + 40*25 + 50*30 = 200 + 600 + 1000 + 1500 = 3300.0
    assert data["total_at_risk_purchase_value"] == 3300.0

    # At-risk MRP value: 20*15 + 30*30 + 40*40 + 50*50 = 300 + 900 + 1600 + 2500 = 5300.0
    assert data["total_at_risk_mrp_value"] == 5300.0

    # Validate each bucket
    buckets = {b["tier"]: b for b in data["buckets"]}

    assert buckets["EXPIRED"]["batch_count"] == 1
    assert buckets["EXPIRED"]["total_units"] == 20.0
    assert buckets["EXPIRED"]["total_purchase_value"] == 200.0

    assert buckets["CRITICAL_30"]["batch_count"] == 1
    assert buckets["CRITICAL_30"]["total_units"] == 30.0
    assert buckets["CRITICAL_30"]["total_purchase_value"] == 600.0

    assert buckets["NEAR_60"]["batch_count"] == 1
    assert buckets["NEAR_60"]["total_units"] == 40.0
    assert buckets["NEAR_60"]["total_purchase_value"] == 1000.0

    assert buckets["ATTENTION_90"]["batch_count"] == 1
    assert buckets["ATTENTION_90"]["total_units"] == 50.0
    assert buckets["ATTENTION_90"]["total_purchase_value"] == 1500.0

    assert buckets["SAFE"]["batch_count"] == 1
    assert buckets["SAFE"]["total_units"] == 100.0
    assert buckets["SAFE"]["total_purchase_value"] == 5000.0


def test_expiry_buckets_tier_filter_query_param(live_client: TestClient):
    """Test filtering expiry buckets by tier query parameter."""
    store_id = "test-store-p6"

    res = live_client.get(f"/api/v1/stores/{store_id}/inventory/expiry-buckets?tier=CRITICAL_30")
    assert res.status_code == 200, res.text
    data = res.json()

    # Batches list should only contain CRITICAL_30 batches
    assert len(data["batches"]) == 1
    assert data["batches"][0]["tier"] == "CRITICAL_30"
    assert data["batches"][0]["batch_number"] == "B-CRIT-02"


# ==============================================================================
# Segregation & Quarantine Tests
# ==============================================================================

def test_segregate_expired_batch_success(live_client: TestClient):
    """Test segregating expired lot decrements active stock and appends audit transaction."""
    store_id = "test-store-p6"

    res = live_client.post(
        f"/api/v1/stores/{store_id}/batches/B-EXP-01/segregate-expired",
        json={
            "quantity": 15.0,
            "reason": "Damaged / expired lot quarantined in chemical bin",
            "idempotency_key": "IDEM-SEGREGATE-001",
            "disposal_method": "INCINERATION_QUARANTINE",
            "actor_id": "AUDITOR-SMITH",
        },
    )
    assert res.status_code == 201, res.text
    tx = res.json()

    assert tx["batch_number"] == "B-EXP-01"
    assert tx["movement_type"] == "ADJUSTMENT_SUBTRACT"
    assert tx["quantity"] == -15.0
    assert tx["source_document"]["document_type"] == "STOCK_AUDIT"
    assert "INCINERATION_QUARANTINE" in tx["notes"]

    # Verify stock decremented from 20 to 5
    b = live_client.get(f"/api/v1/stores/{store_id}/batches/B-EXP-01").json()
    assert b["current_quantity"] == 5.0


def test_segregate_expired_batch_rejects_unexpired_batch(live_client: TestClient):
    """Test that attempting to segregate an unexpired batch fails with HTTP 400 BATCH_NOT_EXPIRED."""
    store_id = "test-store-p6"

    res = live_client.post(
        f"/api/v1/stores/{store_id}/batches/B-SAFE-05/segregate-expired",
        json={
            "quantity": 10.0,
            "reason": "Premature segregation attempt",
            "idempotency_key": "IDEM-SEGREGATE-INVALID",
        },
    )
    assert res.status_code == 400, res.text
    err = res.json()
    assert err["detail"]["code"] == "BATCH_NOT_EXPIRED"

    # Verify stock remains 100
    b = live_client.get(f"/api/v1/stores/{store_id}/batches/B-SAFE-05").json()
    assert b["current_quantity"] == 100.0


def test_segregate_expired_batch_rejects_overdraft(live_client: TestClient):
    """Test that requesting more stock than available aborts with HTTP 400 INSUFFICIENT_STOCK."""
    store_id = "test-store-p6"

    # Only 5.0 units remain in B-EXP-01. Request 20.0
    res = live_client.post(
        f"/api/v1/stores/{store_id}/batches/B-EXP-01/segregate-expired",
        json={
            "quantity": 20.0,
            "reason": "Overdraft segregation",
            "idempotency_key": "IDEM-SEGREGATE-OVERDRAFT",
        },
    )
    assert res.status_code == 400, res.text
    assert res.json()["detail"]["code"] == "INSUFFICIENT_STOCK"

    # Stock remains 5.0
    b = live_client.get(f"/api/v1/stores/{store_id}/batches/B-EXP-01").json()
    assert b["current_quantity"] == 5.0


# ==============================================================================
# Supplier Return Tests
# ==============================================================================

def test_return_batch_to_supplier_success(live_client: TestClient):
    """Test processing supplier return decrements active lot and logs RETURN_OUT transaction."""
    store_id = "test-store-p6"

    res = live_client.post(
        f"/api/v1/stores/{store_id}/batches/B-CRIT-02/return-to-supplier",
        json={
            "quantity": 10.0,
            "supplier_id": "SUP-CIPLA-01",
            "supplier_name": "Cipla Pharmaceuticals India",
            "reason": "Near-expiry credit return (expiring in 15 days)",
            "supplier_invoice_reference": "INV-CIPLA-8891",
            "credit_note_reference": "CN-2026-9912",
            "idempotency_key": "IDEM-SUP-RETURN-001",
            "actor_id": "PHARMACIST-RETURNS",
        },
    )
    assert res.status_code == 201, res.text
    tx = res.json()

    assert tx["batch_number"] == "B-CRIT-02"
    assert tx["movement_type"] == "RETURN_OUT"
    assert tx["quantity"] == -10.0
    assert tx["source_document"]["document_type"] == "SUPPLIER_RETURN"
    assert tx["source_document"]["document_number"] == "CN-2026-9912"
    assert "Cipla Pharmaceuticals" in tx["notes"]

    # Verify stock decremented from 30 to 20
    b = live_client.get(f"/api/v1/stores/{store_id}/batches/B-CRIT-02").json()
    assert b["current_quantity"] == 20.0


def test_return_batch_to_supplier_rejects_overdraft(live_client: TestClient):
    """Test that attempting to return more than available stock is rejected."""
    store_id = "test-store-p6"

    # 20.0 remain in B-CRIT-02. Request 50.0
    res = live_client.post(
        f"/api/v1/stores/{store_id}/batches/B-CRIT-02/return-to-supplier",
        json={
            "quantity": 50.0,
            "supplier_id": "SUP-CIPLA-01",
            "reason": "Overdraft return attempt",
            "idempotency_key": "IDEM-SUP-RETURN-OVERDRAFT",
        },
    )
    assert res.status_code == 400, res.text
    assert res.json()["detail"]["code"] == "INSUFFICIENT_STOCK"

    # Stock remains 20.0
    b = live_client.get(f"/api/v1/stores/{store_id}/batches/B-CRIT-02").json()
    assert b["current_quantity"] == 20.0


def test_idempotency_conflict_on_segregation_and_returns(live_client: TestClient):
    """Test that duplicate idempotency keys return HTTP 409 Conflict."""
    store_id = "test-store-p6"

    # Duplicate Segregation Key
    r1 = live_client.post(
        f"/api/v1/stores/{store_id}/batches/B-EXP-01/segregate-expired",
        json={
            "quantity": 1.0,
            "reason": "Duplicate test",
            "idempotency_key": "IDEM-SEGREGATE-001",  # Reused key
        },
    )
    assert r1.status_code == 409, r1.text
    assert r1.json()["detail"]["code"] == "DUPLICATE_IDEMPOTENCY_KEY"

    # Duplicate Supplier Return Key
    r2 = live_client.post(
        f"/api/v1/stores/{store_id}/batches/B-CRIT-02/return-to-supplier",
        json={
            "quantity": 1.0,
            "supplier_id": "SUP-CIPLA-01",
            "reason": "Duplicate test",
            "idempotency_key": "IDEM-SUP-RETURN-001",  # Reused key
        },
    )
    assert r2.status_code == 409, r2.text
    assert r2.json()["detail"]["code"] == "DUPLICATE_IDEMPOTENCY_KEY"
