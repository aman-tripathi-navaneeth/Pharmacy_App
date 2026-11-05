import asyncio
from datetime import date, datetime, timedelta

import pytest
from fastapi import FastAPI
from fastapi.testclient import TestClient

from app.modules.today_dashboard_reports import deps, service
from app.modules.today_dashboard_reports.facts import CreditFact, ExpiryFact, RefillFact
from app.modules.today_dashboard_reports.repository import InMemoryTaskStateRepo
from app.modules.today_dashboard_reports.router import router
from app.modules.today_dashboard_reports.service import IST
from app.modules.today_dashboard_reports.sources import PostgresSalesReportSource

NOW = datetime(2026, 10, 12, 18, 40, tzinfo=IST)
OWNER = {"X-Dev-Role": "owner", "X-Dev-Stores": "demo-store"}
STAFF = {"X-Dev-Role": "staff", "X-Dev-Stores": "demo-store"}


class FakeSource:
    def __init__(self, name, facts=None, error=None, delay=0.0):
        self.name, self._facts, self._error, self._delay = name, facts or [], error, delay

    async def fetch(self, store_id, now):
        if self._delay:
            await asyncio.sleep(self._delay)
        if self._error:
            raise self._error
        return self._facts


class FakeSummaryPool:
    def __init__(self):
        self.values = None

    async def execute(self, _query, *args):
        if self.values is None:
            self.values = args

    async def fetchrow(self, _query, *_args):
        if self.values is None:
            return None
        values = self.values
        return {
            "summary_date": values[1],
            "total_sales_amount": values[2],
            "total_purchases_amount": values[3],
            "udhaar_collected_amount": values[4],
            "udhaar_issued_amount": values[5],
            "expired_stock_value": values[6],
            "low_stock_sku_count": values[7],
            "created_at": NOW,
        }


class MissingSalesTablePool:
    def __init__(self):
        self.calls = []

    async def fetchval(self, query, *_args):
        self.calls.append(query)
        return False


def make_client(sources, now=NOW):
    app = FastAPI()
    app.include_router(router, prefix="/api/v1")
    repo = InMemoryTaskStateRepo()
    app.dependency_overrides[deps.get_sources] = lambda: sources
    app.dependency_overrides[deps.get_now] = lambda: now
    app.dependency_overrides[deps.get_repo] = lambda: repo
    return TestClient(app), app


def default_sources():
    return [
        FakeSource("inventory", [ExpiryFact(key="expiry:b1", medicine="Augmentin 625", batch_no="AB1", quantity_text="18 strips",
                                            days_to_expiry=12, value_paise=720000)]),
        FakeSource("refills", [RefillFact(key="refill:c1", customer="Lakshmi", purpose="BP", medicine_text="x", days_overdue=3)]),
        FakeSource("credit", [CreditFact(key="credit:c2", customer="Venkata Rao", balance_paise=425000, days_since_payment=45)]),
    ]


URL = "/api/v1/stores/demo-store/dashboard/today"


def test_today_returns_ranked_tasks_counts_and_glance():
    client, _ = make_client(default_sources())
    r = client.get(URL, headers=OWNER)
    assert r.status_code == 200
    body = r.json()
    assert [t["key"] for t in body["tasks"]] == ["credit:c2", "expiry:b1", "refill:c1"]
    assert body["counts"] == {"urgent": 2, "soon": 1, "routine": 0, "snoozed": 0, "done_today": 0}
    assert body["glance"]["expiring_30_days_value_paise"] == 720000
    assert body["glance"]["credit_to_collect_paise"] == 425000
    assert all(s["ok"] for s in body["source_status"])


def test_failed_source_gives_partial_result_not_an_error():
    sources = default_sources()
    sources[2] = FakeSource("credit", error=RuntimeError("boom"))
    client, _ = make_client(sources)
    body = client.get(URL, headers=OWNER).json()
    assert {t["key"] for t in body["tasks"]} == {"expiry:b1", "refill:c1"}
    assert {"source": "credit", "ok": False, "error": "unavailable"} in body["source_status"]
    assert body["glance"]["credit_to_collect_paise"] is None  # unknown, never shown as zero
    assert body["glance"]["expiring_30_days_value_paise"] == 720000


def test_slow_source_times_out(monkeypatch):
    monkeypatch.setattr(service, "SOURCE_TIMEOUT_SECONDS", 0.05)
    sources = default_sources()
    sources[2] = FakeSource("credit", delay=0.5)
    client, _ = make_client(sources)
    body = client.get(URL, headers=OWNER).json()
    assert {"source": "credit", "ok": False, "error": "timeout"} in body["source_status"]


def test_staff_never_receive_credit_data():
    client, _ = make_client(default_sources())
    body = client.get(URL, headers=STAFF).json()
    assert all(t["category"] != "credit" for t in body["tasks"])
    assert body["glance"]["credit_to_collect_paise"] is None
    assert "Venkata" not in client.get(URL, headers=STAFF).text


def test_other_store_is_forbidden_with_stable_error_shape():
    client, _ = make_client(default_sources())
    r = client.get("/api/v1/stores/other-store/dashboard/today", headers=OWNER)
    assert r.status_code == 403
    assert r.json() == {"detail": "You do not have access to this store.", "code": "STORE_FORBIDDEN"}


def test_auth_stub_is_off_outside_development(monkeypatch):
    from app.core.config import get_settings
    client, app = make_client(default_sources())
    s = get_settings().model_copy(update={"app_env": "production"})
    app.dependency_overrides[get_settings] = lambda: s
    r = client.get(URL, headers=OWNER)
    assert r.status_code == 401 and r.json()["code"] == "AUTH_NOT_CONFIGURED"


def test_category_filter_and_counts_stay_whole():
    client, _ = make_client(default_sources())
    body = client.get(URL + "?category=expiry", headers=OWNER).json()
    assert [t["key"] for t in body["tasks"]] == ["expiry:b1"]
    assert body["counts"]["urgent"] == 2  # counts are not affected by the filter


def snooze_url(key): return f"/api/v1/stores/demo-store/dashboard/tasks/{key}/snooze"
def done_url(key): return f"/api/v1/stores/demo-store/dashboard/tasks/{key}/done"
def reopen_url(key): return f"/api/v1/stores/demo-store/dashboard/tasks/{key}/reopen"


def test_snooze_hides_task_and_is_idempotent():
    client, _ = make_client(default_sources())
    for _ in range(2):  # repeating must not change the result
        r = client.post(snooze_url("expiry:b1"), json={"until": "2026-10-13"}, headers=OWNER)
        assert r.status_code == 200 and r.json()["status"] == "snoozed"
    body = client.get(URL, headers=OWNER).json()
    assert "expiry:b1" not in [t["key"] for t in body["tasks"]]
    assert body["counts"]["snoozed"] == 1 and body["counts"]["urgent"] == 1
    shown = client.get(URL + "?include_hidden=true", headers=OWNER).json()
    assert [t["state"] for t in shown["tasks"] if t["key"] == "expiry:b1"] == ["snoozed"]


def test_snooze_returns_when_date_arrives():
    client, app = make_client(default_sources())
    client.post(snooze_url("expiry:b1"), json={"until": "2026-10-13"}, headers=OWNER)
    app.dependency_overrides[deps.get_now] = lambda: NOW + timedelta(days=1)
    assert "expiry:b1" in [t["key"] for t in client.get(URL, headers=OWNER).json()["tasks"]]


@pytest.mark.parametrize("until", ["2026-10-12", "2026-10-01", "2026-11-12"])
def test_snooze_rejects_bad_dates(until):
    client, _ = make_client(default_sources())
    r = client.post(snooze_url("expiry:b1"), json={"until": until}, headers=OWNER)
    assert r.status_code == 400 and r.json()["code"] == "INVALID_SNOOZE_DATE"


def test_snooze_accepts_the_30_day_limit():
    client, _ = make_client(default_sources())
    assert client.post(snooze_url("expiry:b1"), json={"until": "2026-11-11"}, headers=OWNER).status_code == 200


def test_snooze_schema_error_is_422():
    client, _ = make_client(default_sources())
    assert client.post(snooze_url("expiry:b1"), json={"until": "not-a-date"}, headers=OWNER).status_code == 422


def test_bad_task_key_is_400():
    client, _ = make_client(default_sources())
    r = client.post(done_url("nonsense"), headers=OWNER)
    assert r.status_code == 400 and r.json()["code"] == "INVALID_TASK_KEY"


def test_done_hides_for_today_and_returns_tomorrow():
    client, app = make_client(default_sources())
    assert client.post(done_url("credit:c2"), headers=OWNER).json()["status"] == "done"
    body = client.get(URL, headers=OWNER).json()
    assert "credit:c2" not in [t["key"] for t in body["tasks"]] and body["counts"]["done_today"] == 1
    app.dependency_overrides[deps.get_now] = lambda: NOW + timedelta(days=1)
    assert "credit:c2" in [t["key"] for t in client.get(URL, headers=OWNER).json()["tasks"]]


def test_reopen_brings_task_back_and_is_safe_to_repeat():
    client, _ = make_client(default_sources())
    client.post(done_url("credit:c2"), headers=OWNER)
    for _ in range(2):
        assert client.post(reopen_url("credit:c2"), headers=OWNER).json()["status"] == "open"
    assert "credit:c2" in [t["key"] for t in client.get(URL, headers=OWNER).json()["tasks"]]


def test_state_is_per_store():
    client, _ = make_client(default_sources())
    h = {"X-Dev-Role": "owner", "X-Dev-Stores": "demo-store,store-b"}
    client.post(done_url("credit:c2"), headers=h)
    other = client.get("/api/v1/stores/store-b/dashboard/today", headers=h).json()
    assert "credit:c2" in [t["key"] for t in other["tasks"]]


def test_actions_also_check_store_access():
    client, _ = make_client(default_sources())
    r = client.post("/api/v1/stores/other-store/dashboard/tasks/credit:c2/done", headers=OWNER)
    assert r.status_code == 403 and r.json()["code"] == "STORE_FORBIDDEN"


# --- Reports (Summary and Purchases tabs) ---


def test_daily_summary_is_pending_when_nothing_is_confirmed():
    client, _ = make_client(default_sources())
    r = client.get("/api/v1/stores/demo-store/dashboard/reports/daily-summary", headers=OWNER)
    assert r.status_code == 200
    body = r.json()
    assert body["confirmed"] is False
    assert body["summary_date"] == "2026-10-12"
    assert body["total_sales_paise"] is None  # waiting, never zero


def test_daily_summary_accepts_an_explicit_date():
    client, _ = make_client(default_sources())
    r = client.get(
        "/api/v1/stores/demo-store/dashboard/reports/daily-summary?date=2026-10-10", headers=OWNER
    )
    assert r.status_code == 200 and r.json()["summary_date"] == "2026-10-10"


def test_trend_returns_seven_days_when_the_pool_exists_only():
    # No pool in the test app: the response is honestly empty, not fabricated.
    client, _ = make_client(default_sources())
    r = client.get("/api/v1/stores/demo-store/dashboard/reports/trend", headers=OWNER)
    assert r.status_code == 200 and r.json() == {"points": [], "error": "Database not configured"}


def test_stock_now_is_unavailable_without_a_database():
    client, _ = make_client(default_sources())
    body = client.get("/api/v1/stores/demo-store/dashboard/reports/stock-now", headers=OWNER).json()
    assert body["available"] is False and body["expiring_30"] is None


def test_purchase_register_is_unavailable_without_a_database():
    client, _ = make_client(default_sources())
    body = client.get(
        "/api/v1/stores/demo-store/dashboard/reports/purchase-register?q=INV", headers=OWNER
    ).json()
    assert body["available"] is False and body["rows"] == [] and body["total_paise"] is None


def test_sales_source_returns_empty_without_querying_a_missing_table():
    pool = MissingSalesTablePool()
    facts = asyncio.run(PostgresSalesReportSource(pool).fetch("demo-store", NOW))
    assert facts == []
    assert len(pool.calls) == 1
    assert "to_regclass" in pool.calls[0]


def test_purchase_register_paginates_and_returns_total_filtered_count():
    class PurchasePool:
        def __init__(self):
            self.invoice_query_args = None

        async def fetchval(self, query, *_args):
            return 1 if "to_regclass" in query else 123

        async def fetch(self, query, *args):
            if "FROM purchase_invoices pi" in query:
                self.invoice_query_args = args
                return [{
                    "id": 10,
                    "invoice_no": "INV-10",
                    "invoice_date": date(2026, 10, 10),
                    "supplier": "Supplier",
                    "total_amount": 120.50,
                    "item_count": 1,
                }]
            return []

    pool = PurchasePool()
    client, app = make_client(default_sources())
    app.dependency_overrides[deps.get_pool] = lambda: pool

    response = client.get(
        "/api/v1/stores/demo-store/dashboard/reports/purchase-register"
        "?limit=10&offset=20",
        headers=OWNER,
    )

    assert response.status_code == 200
    assert response.json()["total_count"] == 123
    assert len(response.json()["rows"]) == 1
    assert pool.invoice_query_args[-2:] == (10, 20)


def test_daily_summary_confirmation_requires_explicit_nonnegative_values():
    client, _ = make_client(default_sources())
    url = "/api/v1/stores/demo-store/dashboard/reports/confirm-summary"
    assert client.post(url, headers=OWNER).status_code == 422
    payload = {
        "total_sales_paise": -1,
        "total_purchases_paise": 0,
        "udhaar_collected_paise": 0,
        "udhaar_issued_paise": 0,
        "expired_stock_value_paise": 0,
        "low_stock_sku_count": 0,
    }
    assert client.post(url, json=payload, headers=OWNER).status_code == 422
    assert client.post(
        url,
        json={
            "total_sales_paise": 0,
            "total_purchases_paise": 0,
            "udhaar_collected_paise": 0,
            "udhaar_issued_paise": 0,
            "expired_stock_value_paise": 0,
            "low_stock_sku_count": 0,
        },
        headers=STAFF,
    ).status_code == 403


def test_daily_summary_confirmation_is_idempotent_but_cannot_overwrite():
    client, app = make_client(default_sources())
    pool = FakeSummaryPool()
    app.dependency_overrides[deps.get_pool] = lambda: pool
    url = "/api/v1/stores/demo-store/dashboard/reports/confirm-summary"
    payload = {
        "total_sales_paise": 12345,
        "total_purchases_paise": 8000,
        "udhaar_collected_paise": 100,
        "udhaar_issued_paise": 200,
        "expired_stock_value_paise": 300,
        "low_stock_sku_count": 4,
    }

    first = client.post(url, json=payload, headers=OWNER)
    repeated = client.post(url, json=payload, headers=OWNER)
    changed = client.post(
        url, json={**payload, "total_sales_paise": 999}, headers=OWNER
    )

    assert first.status_code == 200 and first.json()["confirmed"] is True
    assert repeated.status_code == 200
    assert changed.status_code == 409
    assert changed.json()["code"] == "SUMMARY_ALREADY_CONFIRMED"


@pytest.mark.parametrize(
    "path",
    [
        "/api/v1/stores/other-store/dashboard/reports/daily-summary",
        "/api/v1/stores/other-store/dashboard/reports/trend",
        "/api/v1/stores/other-store/dashboard/reports/stock-now",
        "/api/v1/stores/other-store/dashboard/reports/purchase-register",
    ],
)
def test_report_endpoints_check_store_access(path):
    client, _ = make_client(default_sources())
    assert client.get(path, headers=OWNER).status_code == 403
