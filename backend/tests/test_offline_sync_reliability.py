"""Tests for Module 12: Offline Sync, Integration & Reliability FastAPI endpoints."""

from fastapi.testclient import TestClient

from app.main import app

client = TestClient(app)


def test_integration_health_endpoints() -> None:
    res = client.get("/api/integrations/health")
    assert res.status_code == 200
    body = res.json()
    assert body["overall"] == "OPERATIONAL"
    assert len(body["modules"]) == 8

    recheck = client.post(
        "/api/integrations/health/inventory/check",
        json={"storeId": "00000000-0000-4000-9000-000000000001"},
    )
    assert recheck.status_code == 200
    assert recheck.json()["module"]["key"] == "inventory"


def test_languages_and_translations_endpoints() -> None:
    res = client.get("/api/languages")
    assert res.status_code == 200
    body = res.json()
    assert body["defaultLanguage"] == "en"
    codes = [lang["code"] for lang in body["languages"]]
    assert {"en", "hi", "ta", "te"}.issubset(set(codes))

    cat = client.get("/api/translations/en")
    assert cat.status_code == 200
    cat_body = cat.json()
    assert cat_body["languageCode"] == "en"
    assert "home.title" in cat_body["messages"]

    etag = cat.headers.get("etag")
    assert etag is not None
    not_mod = client.get("/api/translations/en", headers={"if-none-match": etag})
    assert not_mod.status_code == 304


def test_product_tour_endpoint() -> None:
    res = client.get("/api/product-tour/latest")
    assert res.status_code == 200
    body = res.json()
    assert body["version"] == "2026.10.1"
    assert len(body["steps"]) == 6


def test_sync_status_and_pull_endpoints() -> None:
    status_res = client.get("/api/sync/status")
    assert status_res.status_code == 200
    assert "counts" in status_res.json()

    pull_res = client.get("/api/sync/pull")
    assert pull_res.status_code == 200
    assert "changes" in pull_res.json()
    assert "nextCursor" in pull_res.json()

