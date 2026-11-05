
from datetime import datetime, timedelta, timezone
from types import SimpleNamespace

from fastapi.testclient import TestClient

from app.main import app


class FakeCollection:
    def __init__(self, documents):
        self.documents = documents

    async def find_one(self, query):
        for document in self.documents:
            if all(document.get(key) == value for key, value in query.items()):
                return document
        return None

    def find(self, query):
        return FakeCursor([
            document for document in self.documents
            if all(document.get(key) == value for key, value in query.items())
        ])


class FakeCursor:
    def __init__(self, documents):
        self.documents = documents
        self._iterator = None

    def __aiter__(self):
        self._iterator = iter(self.documents)
        return self

    async def __anext__(self):
        try:
            return next(self._iterator)
        except StopIteration:
            raise StopAsyncIteration


def make_fake_db():
    today = datetime.now(
        timezone(timedelta(hours=5, minutes=30))
    ).date()

    batches = [
        {
            "_id": "b-expired",
            "store_id": "store_test",
            "product_id": "p1",
            "batch_number": "OLD-01",
            "expiry_date": datetime.combine(
                today - timedelta(days=5), datetime.min.time()
            ),
        },
        {
            "_id": "b-critical",
            "store_id": "store_test",
            "product_id": "p2",
            "batch_number": "SOON-02",
            "expiry_date": datetime.combine(
                today + timedelta(days=10), datetime.min.time()
            ),
        },
        {
            "_id": "b-warning",
            "store_id": "store_test",
            "product_id": "p1",
            "batch_number": "LATER-03",
            "expiry_date": datetime.combine(
                today + timedelta(days=60), datetime.min.time()
            ),
        },
        {
            "_id": "b-ok",
            "store_id": "store_test",
            "product_id": "p2",
            "batch_number": "FUTURE-04",
            "expiry_date": datetime.combine(
                today + timedelta(days=150), datetime.min.time()
            ),
        },
        {
            "_id": "b-no-expiry",
            "store_id": "store_test",
            "product_id": "p1",
            "batch_number": "NONE-05",
            "expiry_date": None,
        },
    ]

    products = [
        {
            "_id": "p1",
            "name": "Paracetamol",
            "base_unit": "tablet",
            "pack_size_base": 10,
            "pack_unit": "strip",
        },
        {
            "_id": "p2",
            "name": "Amoxicillin",
            "base_unit": "capsule",
            "pack_size_base": 10,
            "pack_unit": "strip",
        },
    ]

    balances = [
        {
            "store_id": "store_test",
            "batch_id": batch["_id"],
            "product_id": batch["product_id"],
            "quantity_base": 20,
        }
        for batch in batches
    ]

    return SimpleNamespace(
        stock_settings=FakeCollection([
            {
                "store_id": "store_test",
                "expiry_critical_days": 30,
                "expiry_warning_days": 90,
            }
        ]),
        batches=FakeCollection(batches),
        products=FakeCollection(products),
        stock_balances=FakeCollection(balances),
    )


def test_expiry_summary_counts_all_statuses():
    previous_db = getattr(app.state, "db", None)
    try:
        with TestClient(app) as client:
            app.state.db = make_fake_db()
            response = client.get(
                "/api/v1/stores/store_test/inventory/expiry/summary"
            )

        assert response.status_code == 200
        assert response.json() == {
            "expired": 1,
            "critical": 1,
            "warning": 1,
            "ok": 1,
            "no_expiry": 1,
        }
    finally:
        app.state.db = previous_db


def test_expiry_filter_by_status():
    previous_db = getattr(app.state, "db", None)
    try:
        with TestClient(app) as client:
            app.state.db = make_fake_db()
            response = client.get(
                "/api/v1/stores/store_test/inventory/expiry?status=EXPIRED"
            )

        assert response.status_code == 200
        assert response.json()["total"] == 1
        assert response.json()["items"][0]["batch_number"] == "OLD-01"
    finally:
        app.state.db = previous_db


def test_expiry_search_matches_product_and_batch():
    previous_db = getattr(app.state, "db", None)
    try:
        with TestClient(app) as client:
            app.state.db = make_fake_db()
            product_response = client.get(
                "/api/v1/stores/store_test/inventory/expiry?q=paracetamol"
            )
            batch_response = client.get(
                "/api/v1/stores/store_test/inventory/expiry?q=SOON-02"
            )

        assert product_response.status_code == 200
        assert product_response.json()["total"] == 3
        assert batch_response.status_code == 200
        assert batch_response.json()["total"] == 1
    finally:
        app.state.db = previous_db


def test_expiry_pagination():
    previous_db = getattr(app.state, "db", None)
    try:
        with TestClient(app) as client:
            app.state.db = make_fake_db()
            response = client.get(
                "/api/v1/stores/store_test/inventory/expiry?page=1&page_size=2"
            )

        assert response.status_code == 200
        assert response.json()["total"] == 5
        assert len(response.json()["items"]) == 2
    finally:
        app.state.db = previous_db


def test_expiry_rejects_invalid_status():
    previous_db = getattr(app.state, "db", None)
    try:
        with TestClient(app) as client:
            app.state.db = make_fake_db()
            response = client.get(
                "/api/v1/stores/store_test/inventory/expiry?status=INVALID"
            )

        assert response.status_code == 422
        assert response.json()["detail"]["code"] == "INVALID_EXPIRY_STATUS"
    finally:
        app.state.db = previous_db


def test_low_stock_endpoints_require_configured_database():
    previous_db = getattr(app.state, "db", None)
    try:
        with TestClient(app) as client:
            app.state.db = None
            response = client.get(
                "/api/v1/stores/store_test/inventory/low-stock"
            )

        assert response.status_code == 503
        assert response.json()["detail"]["code"] == "DATABASE_NOT_CONFIGURED"
    finally:
        app.state.db = previous_db


def test_reconciliation_reports_inventory_service_unavailable():
    previous_db = getattr(app.state, "db", None)
    try:
        with TestClient(app) as client:
            app.state.db = make_fake_db()
            response = client.get(
                "/api/v1/stores/store_test/inventory/reconciliation"
            )

        assert response.status_code == 503
        assert (
            response.json()["detail"]["code"]
            == "INVENTORY_SERVICE_UNAVAILABLE"
        )
        assert (
            "No stock was changed"
            in response.json()["detail"]["message"]
        )
    finally:
        app.state.db = previous_db


def test_low_stock_lists_products_at_or_below_threshold():
    previous_db = getattr(app.state, "db", None)
    try:
        db = make_fake_db()
        db.stock_settings.documents[0]["low_stock_thresholds"] = {
            "p1": 65,
            "p2": 45,
        }

        with TestClient(app) as client:
            app.state.db = db
            response = client.get(
                "/api/v1/stores/store_test/inventory/low-stock"
            )

        assert response.status_code == 200
        data = response.json()
        assert data["total"] == 2

        items = {item["product_id"]: item for item in data["items"]}
        assert items["p1"]["status"] == "LOW_STOCK"
        assert items["p1"]["quantity_base"] == 60
        assert items["p1"]["reorder_level_base"] == 65
        assert items["p2"]["status"] == "LOW_STOCK"
        assert items["p2"]["quantity_base"] == 40
        assert items["p2"]["reorder_level_base"] == 45
    finally:
        app.state.db = previous_db


def test_low_stock_omits_products_without_threshold():
    previous_db = getattr(app.state, "db", None)
    try:
        with TestClient(app) as client:
            app.state.db = make_fake_db()
            response = client.get(
                "/api/v1/stores/store_test/inventory/low-stock"
            )

        assert response.status_code == 200
        assert response.json() == {"items": [], "total": 0}
    finally:
        app.state.db = previous_db
