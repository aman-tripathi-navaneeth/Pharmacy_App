from fastapi.testclient import TestClient

from app.main import app, settings


def test_health_endpoint() -> None:
    with TestClient(app) as client:
        response = client.get("/health")
    assert response.status_code == 200
    assert response.json() == {"status": "ok"}


def test_ready_without_database_configuration(monkeypatch) -> None:
    monkeypatch.setattr(settings, "postgres_url", "")
    monkeypatch.setattr(settings, "database_url", "")
    monkeypatch.setattr(settings, "DATABASE_URL", "")
    with TestClient(app) as client:
        response = client.get("/ready")
    assert response.status_code == 503
    assert response.json()["code"] == "DATABASE_NOT_CONFIGURED"
