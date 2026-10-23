from fastapi.testclient import TestClient

from app.main import app, settings


def test_health_endpoint() -> None:
    with TestClient(app) as client:
        response = client.get("/health")
    assert response.status_code == 200
    assert response.json() == {"status": "ok"}


def test_ready_without_database_configuration(monkeypatch) -> None:
    # Pin the setting to empty so this test passes no matter what POSTGRES_URL the
    # developer has in backend/.env. It tests the unconfigured-database behavior,
    # not the local environment.
    monkeypatch.setattr(settings, "postgres_url", "")
    with TestClient(app) as client:
        response = client.get("/ready")
    assert response.status_code == 503
    assert response.json()["detail"]["code"] == "DATABASE_NOT_CONFIGURED"
