"""Automated integration tests for Phase 7: Low Stock Alerts, Reorder Thresholds & Safety Stock Rules."""

from datetime import datetime, timedelta, timezone
import pytest
from fastapi.testclient import TestClient



# ==============================================================================
# Threshold Configuration & Validation Tests
# ==============================================================================

def test_threshold_override_persistence_and_retrieval(live_client: TestClient):
    """Test custom threshold configuration persistence and retrieval."""
    store_id = "test-store-p7"
    prod_id = "prod-dolo-650"

    # 1. Retrieve default thresholds when unconfigured
    default_res = live_client.get(f"/api/v1/stores/{store_id}/inventory/thresholds/{prod_id}")
    assert default_res.status_code == 200
    default_data = default_res.json()
    assert default_data["product_id"] == prod_id
    assert default_data["reorder_point"] == 50.0
    assert default_data["safety_stock_level"] == 20.0
    assert default_data["reorder_quantity"] == 100.0

    # 2. Update with store-specific thresholds
    update_res = live_client.post(
        f"/api/v1/stores/{store_id}/inventory/thresholds/{prod_id}",
        json={
            "reorder_point": 80.0,
            "safety_stock_level": 30.0,
            "reorder_quantity": 200.0,
            "lead_time_days": 4,
            "max_stock_level": 500.0,
            "notes": "High demand analgesic in monsoon season",
        },
    )
    assert update_res.status_code == 200
    saved = update_res.json()
    assert saved["store_id"] == store_id
    assert saved["product_id"] == prod_id
    assert saved["reorder_point"] == 80.0
    assert saved["safety_stock_level"] == 30.0
    assert saved["reorder_quantity"] == 200.0
    assert saved["lead_time_days"] == 4
    assert saved["notes"] == "High demand analgesic in monsoon season"

    # 3. Retrieve stored configuration
    get_res = live_client.get(f"/api/v1/stores/{store_id}/inventory/thresholds/{prod_id}")
    assert get_res.status_code == 200
    fetched = get_res.json()
    assert fetched["reorder_point"] == 80.0
    assert fetched["safety_stock_level"] == 30.0
    assert fetched["reorder_quantity"] == 200.0


def test_threshold_validation_rejects_safety_greater_than_reorder(live_client: TestClient):
    """Test validator rejects safety_stock_level > reorder_point."""
    store_id = "test-store-p7"
    prod_id = "prod-invalid-thresh"

    res = live_client.post(
        f"/api/v1/stores/{store_id}/inventory/thresholds/{prod_id}",
        json={
            "reorder_point": 30.0,
            "safety_stock_level": 50.0,  # Invalid: safety cannot exceed reorder point
            "reorder_quantity": 100.0,
        },
    )
    assert res.status_code in (400, 422)


# ==============================================================================
# Stock Alert Severities & Calculations Tests
# ==============================================================================

def test_low_stock_severity_out_of_stock(live_client: TestClient):
    """Test OUT_OF_STOCK triggered when unexpired stock is 0."""
    store_id = "test-store-p7"
    prod_id = "prod-stockout-med"

    # Configure threshold for product without any batches
    live_client.post(
        f"/api/v1/stores/{store_id}/inventory/thresholds/{prod_id}",
        json={
            "reorder_point": 50.0,
            "safety_stock_level": 20.0,
            "reorder_quantity": 100.0,
        },
    )

    alerts_res = live_client.get(f"/api/v1/stores/{store_id}/inventory/low-stock-alerts")
    assert alerts_res.status_code == 200
    data = alerts_res.json()

    alert = next((a for a in data["alerts"] if a["product_id"] == prod_id), None)
    assert alert is not None
    assert alert["severity"] == "OUT_OF_STOCK"
    assert alert["current_unexpired_stock"] == 0.0
    assert alert["suggested_reorder_quantity"] == 100.0


def test_low_stock_severity_critical_low(live_client: TestClient):
    """Test CRITICAL_LOW triggered when unexpired stock <= safety_stock_level."""
    store_id = "test-store-p7"
    prod_id = "prod-critical-med"
    today = datetime.now(timezone.utc).date()

    # Configure threshold: safety=25, reorder=60, reorder_qty=100
    live_client.post(
        f"/api/v1/stores/{store_id}/inventory/thresholds/{prod_id}",
        json={
            "reorder_point": 60.0,
            "safety_stock_level": 25.0,
            "reorder_quantity": 100.0,
        },
    )

    # Register batch with stock 15 (< 25 safety level)
    live_client.post(
        f"/api/v1/stores/{store_id}/batches",
        json={
            "product_id": prod_id,
            "batch_number": "B-CRIT-01",
            "expiry_date": (today + timedelta(days=120)).isoformat(),
            "current_quantity": 15.0,
            "base_unit": "TABLET",
            "initial_quantity": 15.0,
            "purchase_rate": 12.0,
            "mrp": 20.0,
        },
    )

    alerts_res = live_client.get(f"/api/v1/stores/{store_id}/inventory/low-stock-alerts")
    assert alerts_res.status_code == 200
    data = alerts_res.json()

    alert = next((a for a in data["alerts"] if a["product_id"] == prod_id), None)
    assert alert is not None
    assert alert["severity"] == "CRITICAL_LOW"
    assert alert["current_unexpired_stock"] == 15.0
    # Suggested reorder: max(100, (60 * 2) - 15) = max(100, 105) = 105.0
    assert alert["suggested_reorder_quantity"] == 105.0
    # Estimated cost: 105 * 12.0 = 1260.0
    assert alert["estimated_reorder_cost"] == 1260.0


def test_low_stock_severity_reorder_recommended(live_client: TestClient):
    """Test REORDER_RECOMMENDED triggered when safety_stock < stock <= reorder_point."""
    store_id = "test-store-p7"
    prod_id = "prod-reorder-med"
    today = datetime.now(timezone.utc).date()

    # Configure threshold: safety=20, reorder=50, reorder_qty=80
    live_client.post(
        f"/api/v1/stores/{store_id}/inventory/thresholds/{prod_id}",
        json={
            "reorder_point": 50.0,
            "safety_stock_level": 20.0,
            "reorder_quantity": 80.0,
        },
    )

    # Register batch with stock 35 (20 < 35 <= 50)
    live_client.post(
        f"/api/v1/stores/{store_id}/batches",
        json={
            "product_id": prod_id,
            "batch_number": "B-REORD-01",
            "expiry_date": (today + timedelta(days=200)).isoformat(),
            "current_quantity": 35.0,
            "base_unit": "CAPSULE",
            "initial_quantity": 35.0,
            "purchase_rate": 25.0,
            "mrp": 40.0,
        },
    )

    alerts_res = live_client.get(f"/api/v1/stores/{store_id}/inventory/low-stock-alerts")
    assert alerts_res.status_code == 200
    data = alerts_res.json()

    alert = next((a for a in data["alerts"] if a["product_id"] == prod_id), None)
    assert alert is not None
    assert alert["severity"] == "REORDER_RECOMMENDED"
    assert alert["current_unexpired_stock"] == 35.0
    # Suggested reorder: max(80, (50 * 2) - 35) = max(80, 65) = 80.0
    assert alert["suggested_reorder_quantity"] == 80.0


def test_low_stock_severity_adequate(live_client: TestClient):
    """Test ADEQUATE classified when stock > reorder_point."""
    store_id = "test-store-p7"
    prod_id = "prod-adequate-med"
    today = datetime.now(timezone.utc).date()

    # Configure threshold: safety=20, reorder=50, reorder_qty=100
    live_client.post(
        f"/api/v1/stores/{store_id}/inventory/thresholds/{prod_id}",
        json={
            "reorder_point": 50.0,
            "safety_stock_level": 20.0,
            "reorder_quantity": 100.0,
        },
    )

    # Register batch with stock 150 (> 50)
    live_client.post(
        f"/api/v1/stores/{store_id}/batches",
        json={
            "product_id": prod_id,
            "batch_number": "B-ADEQ-01",
            "expiry_date": (today + timedelta(days=365)).isoformat(),
            "current_quantity": 150.0,
            "base_unit": "TABLET",
            "initial_quantity": 150.0,
            "purchase_rate": 15.0,
            "mrp": 25.0,
        },
    )

    alerts_res = live_client.get(f"/api/v1/stores/{store_id}/inventory/low-stock-alerts")
    assert alerts_res.status_code == 200
    data = alerts_res.json()

    alert = next((a for a in data["alerts"] if a["product_id"] == prod_id), None)
    assert alert is not None
    assert alert["severity"] == "ADEQUATE"
    assert alert["suggested_reorder_quantity"] == 0.0
    assert alert["estimated_reorder_cost"] == 0.0


# ==============================================================================
# Regulatory Safeguard: Expired Stock Exclusion
# ==============================================================================

def test_expired_stock_excluded_from_safety_thresholds(live_client: TestClient):
    """CRITICAL REGULATORY INVARIANT: Expired stock MUST NOT satisfy safety stock or reorder point.

    Example: Product has 10 units unexpired and 100 units expired.
    Total physical stock = 110 units.
    Safety threshold = 20 units.
    Result MUST be CRITICAL_LOW (10 <= 20), NOT ADEQUATE!
    """
    store_id = "test-store-p7"
    prod_id = "prod-expired-guard-med"
    today = datetime.now(timezone.utc).date()

    # Configure threshold: safety=20, reorder=50
    live_client.post(
        f"/api/v1/stores/{store_id}/inventory/thresholds/{prod_id}",
        json={
            "reorder_point": 50.0,
            "safety_stock_level": 20.0,
            "reorder_quantity": 100.0,
        },
    )

    # Batch 1 (EXPIRED): 100 units (expired 5 days ago)
    live_client.post(
        f"/api/v1/stores/{store_id}/batches",
        json={
            "product_id": prod_id,
            "batch_number": "B-EXP-GUARD-01",
            "expiry_date": (today - timedelta(days=5)).isoformat(),
            "current_quantity": 100.0,
            "base_unit": "TABLET",
            "initial_quantity": 100.0,
            "purchase_rate": 10.0,
            "mrp": 15.0,
        },
    )

    # Batch 2 (UNEXPIRED): 10 units (expires in 120 days)
    live_client.post(
        f"/api/v1/stores/{store_id}/batches",
        json={
            "product_id": prod_id,
            "batch_number": "B-EXP-GUARD-02",
            "expiry_date": (today + timedelta(days=120)).isoformat(),
            "current_quantity": 10.0,
            "base_unit": "TABLET",
            "initial_quantity": 10.0,
            "purchase_rate": 10.0,
            "mrp": 15.0,
        },
    )

    alerts_res = live_client.get(f"/api/v1/stores/{store_id}/inventory/low-stock-alerts")
    assert alerts_res.status_code == 200
    data = alerts_res.json()

    alert = next((a for a in data["alerts"] if a["product_id"] == prod_id), None)
    assert alert is not None
    assert alert["current_unexpired_stock"] == 10.0
    assert alert["expired_stock"] == 100.0
    assert alert["total_stock"] == 110.0
    # Strictly CRITICAL_LOW based on 10 unexpired units <= 20 safety level
    assert alert["severity"] == "CRITICAL_LOW"


# ==============================================================================
# Filtering & Store Isolation Tests
# ==============================================================================

def test_low_stock_severity_and_search_query_filters(live_client: TestClient):
    """Test filtering low stock alerts by severity and search term."""
    store_id = "test-store-p7"

    # 1. Filter by severity=CRITICAL_LOW
    crit_res = live_client.get(f"/api/v1/stores/{store_id}/inventory/low-stock-alerts?severity=CRITICAL_LOW")
    assert crit_res.status_code == 200
    crit_data = crit_res.json()
    assert all(a["severity"] == "CRITICAL_LOW" for a in crit_data["alerts"])

    # 2. Filter by severity=OUT_OF_STOCK
    out_res = live_client.get(f"/api/v1/stores/{store_id}/inventory/low-stock-alerts?severity=OUT_OF_STOCK")
    assert out_res.status_code == 200
    out_data = out_res.json()
    assert all(a["severity"] == "OUT_OF_STOCK" for a in out_data["alerts"])

    # 3. Filter by search=reorder-med
    search_res = live_client.get(f"/api/v1/stores/{store_id}/inventory/low-stock-alerts?search=reorder-med")
    assert search_res.status_code == 200
    search_data = search_res.json()
    assert len(search_data["alerts"]) >= 1
    assert any("reorder-med" in a["product_id"] for a in search_data["alerts"])


def test_low_stock_store_isolation(live_client: TestClient):
    """Test store isolation: threshold overrides in Store 1 do not bleed into Store 2."""
    store1 = "test-store-p7"
    store2 = "other-store-p7"
    prod_id = "prod-isolated-med"

    # Configure custom threshold in Store 1
    live_client.post(
        f"/api/v1/stores/{store1}/inventory/thresholds/{prod_id}",
        json={
            "reorder_point": 99.0,
            "safety_stock_level": 40.0,
            "reorder_quantity": 250.0,
            "notes": "Store 1 specific setting",
        },
    )

    # Store 1 should have custom threshold
    s1_res = live_client.get(f"/api/v1/stores/{store1}/inventory/thresholds/{prod_id}")
    assert s1_res.status_code == 200
    assert s1_res.json()["reorder_point"] == 99.0
    assert s1_res.json()["reorder_quantity"] == 250.0

    # Store 2 should return default threshold (unconfigured)
    s2_res = live_client.get(f"/api/v1/stores/{store2}/inventory/thresholds/{prod_id}")
    assert s2_res.status_code == 200
    assert s2_res.json()["reorder_point"] == 50.0  # default
    assert s2_res.json()["reorder_quantity"] == 100.0  # default
