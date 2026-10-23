# Today Dashboard & Reports (Member 11)

**Status:** Today tasks and Summary/Purchases report screens are implemented. Task facts
and reports use PostgreSQL adapters when the shared tables are available; module-owned
task state and daily summaries are stored in PostgreSQL migrations. Cross-module table
names and columns still need confirmation against the owning modules before production use.

## Endpoints (all under `/api/v1/stores/{store_id}/dashboard`)
| Method | Path | Purpose |
|---|---|---|
| GET | `/today` | Ranked tasks, urgency counts, at-a-glance figures, `source_status`. Query: `category` (repeatable), `include_hidden` |
| POST | `/tasks/{task_key}/snooze` | Body `{"until": "YYYY-MM-DD"}`. Must be after today and within 30 days |
| POST | `/tasks/{task_key}/done` | Hide for the rest of today. Returns tomorrow if the condition still exists |
| POST | `/tasks/{task_key}/reopen` | Bring a snoozed or done task back |
| GET | `/reports/daily-summary` | One day's confirmed summary. Query: `date` (optional) |
| GET | `/reports/trend` | Seven days of confirmed sales/purchase totals; reports database failures |
| GET | `/reports/stock-now` | Current expiry and stock-health figures |
| GET | `/reports/purchase-register` | Confirmed invoices. Query: `q`, `limit` (1-100), `offset` |
| POST | `/reports/confirm-summary` | Owners confirm explicit non-negative totals in a JSON body; same-value retries are safe and changed retries are rejected |

Errors use `{"detail": "...", "code": "..."}`. Codes: `STORE_FORBIDDEN` (403), `ROLE_FORBIDDEN` (403),
`AUTH_NOT_CONFIGURED` (401), `INVALID_TASK_KEY` (400), `INVALID_SNOOZE_DATE` (400). Bad schemas return 422.

## How it works
- `sources.py`: PostgreSQL adapters for the modules the dashboard reads from. A missing or failing source is surfaced as unavailable rather than represented as real zero-valued data.
- `facts.py`: plain facts the adapters return. `engine.py`: rules and ranking (pure functions).
- `service.py`: asks all sources in parallel (1.5 s timeout each). A failing source is listed in
  `source_status` and the rest are still returned. A missing figure is `null`, never zero.
- `repository.py`: snoozed/done state storage. Daily report reads and writes are in `reports.py`.
- `deps.py`: auth and store-access check. **Auth is a development stub** (see below).
- This module never reads other modules' collections and never changes stock.

## Tables owned
- `dashboard_task_state` stores `{store_id, task_key, status, snoozed_until, acted_by, acted_at}`.
  Migration `0001` enforces one state per `(store_id, task_key)`. Without `POSTGRES_URL`,
  task state uses in-memory storage and resets on restart.
- `daily_store_summaries` stores one confirmed report per `(store_id, summary_date)`.
  Migration `0002` creates it. Confirmations require explicit non-negative values; retrying
  the same values is safe, while changing an existing day's figures returns a conflict.

## Decisions made in this slice (change if the team disagrees)
- Money is integer **paise**. Times are India Standard Time (UTC+05:30).
- Snooze and done are **per store**, not per user. `acted_by` records who did it.
- `done` lasts until the end of that business day. `snoozed` lasts until the chosen date, which shows the task again.
- Staff (role `staff`) never receive credit tasks or credit totals in the API response.
- Task `key` is `<category>:<id>`, for example `credit:cust_204`. Source modules decide the id part.
- Field names are `snake_case`.

## Cross-module data contracts to confirm

The adapters query shared PostgreSQL tables directly. Confirm names, columns, status values,
and ownership with the corresponding module owners before merging the complete application.
If the team chooses service/API boundaries instead of direct SQL, replace these adapters.

| Adapter | Owner |
|---|---|
| Inventory, batches and thresholds | Members 5 and 6 |
| Refills and prescriptions | Members 8 and 10 |
| Credit and payments | Member 9 |
| Suppliers and purchase orders | Member 3 |
| Sync queue | Members 4 and 12 |
| Sales invoices and daily summary confirmation | Member 7 |
| Auth in `deps.py` (development headers only) | Member 1 |

## Not tested yet
PostgreSQL migrations, adapters, and report queries still need integration testing against
a live database with the agreed shared schema. The backend unit/API tests use fakes and do
not prove that other modules' schemas match these SQL queries.

## Run
```
cd backend
pytest tests/test_dashboard_reports_engine.py tests/test_dashboard_reports_api.py
alembic upgrade head   # after POSTGRES_URL is set, creates dashboard-owned tables
uvicorn app.main:app --reload
# open http://127.0.0.1:8000/docs and try GET /api/v1/stores/demo-store/dashboard/today
```
Dev headers (optional): `X-Dev-Role: owner|staff`, `X-Dev-Stores: demo-store`.
