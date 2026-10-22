"""Tests for Inventory module connectivity and database readiness checks (PostgreSQL / Relational)."""

import pytest
from fastapi.testclient import TestClient

from app.core.config import get_settings
from app.main import app


def test_settings_configuration_defaults() -> None:
    """Verify that default application settings load correctly without secrets."""
    settings = get_settings()
    assert settings.app_name == "Pharmacy Store Application API"
    assert settings.api_v1_prefix == "/api/v1"
    assert isinstance(settings.parsed_cors_origins, list)
    assert len(settings.parsed_cors_origins) > 0


def test_inventory_connectivity_unconfigured() -> None:
    """When database is unconfigured, inventory endpoint should return 503 DATABASE_NOT_CONFIGURED."""
    app.state.db_engine = None

    with TestClient(app) as client:
        response = client.get("/api/v1/stores/store-123/inventory/connectivity")

    assert response.status_code == 503
    data = response.json()
    assert data["detail"]["code"] == "DATABASE_NOT_CONFIGURED"


def test_ready_endpoint_unconfigured() -> None:
    """When database engine is None, /ready returns 503 DATABASE_NOT_CONFIGURED."""
    app.state.db_engine = None

    with TestClient(app) as client:
        response = client.get("/ready")

    assert response.status_code == 503
    data = response.json()
    assert data["detail"]["code"] == "DATABASE_NOT_CONFIGURED"


def test_inventory_connectivity_success(live_client: TestClient) -> None:
    """When relational engine is active, returns 200 with connection confirmation."""
    response = live_client.get("/api/v1/stores/store-456/inventory/connectivity")
    assert response.status_code == 200
    data = response.json()
    assert data["status"] == "route-ready"
    assert data["database_status"] == "connected"
    assert data["store_id"] == "store-456"
