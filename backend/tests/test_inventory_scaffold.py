from fastapi.testclient import TestClient

from app.main import app


def test_inventory_route_registered() -> None:
    with TestClient(app) as client:
        response = client.get("/api/v1/stores/demo-store/inventory/connectivity")
    # Without Atlas configured the endpoint should clearly refuse, not fake success.
    assert response.status_code == 503
    assert response.json()["detail"]["code"] == "DATABASE_NOT_CONFIGURED"
