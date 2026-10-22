# Inventory, Batches & Stock Ledger (Module 5)

**Status:** Phase 8 (Physical Stock Audits, Cycle Counts & Discrepancy Adjustments) Complete.

## Scope
This module serves as the authoritative source of truth for all pharmacy stock movements, product batches, expiry tracking, and reconciliation. All stock mutations are executed through an immutable append-only stock ledger.

## Collections & Data Model Structure

### 1. `batches`
Stores batch/lot level metadata for medicines in each store:
- `store_id`: Store identifier for isolation (indexed).
- `product_id`: Catalogue product reference (indexed).
- `batch_number`: Manufacturer lot identifier (normalized to uppercase).
- `expiry_date`: Expiry date for FEFO stock allocation (indexed).
- `mrp` / `purchase_rate`: Pricing metadata in INR.
- `current_quantity`: Current stock in base units.
- **Unique Constraint:** `(store_id, product_id, batch_number)`.

### 2. `stock_transactions` (Append-Only Authoritative Ledger)
The immutable audit trail of all inventory movements:
- `store_id`: Store identifier (mandatory).
- `product_id`: Catalogue product ID.
- `batch_id` / `batch_number`: Associated batch when known.
- `movement_type`: `PURCHASE_IN`, `SALES_REPORT_OUT`, `RETURN_IN`, `RETURN_OUT`, `ADJUSTMENT_ADD`, `ADJUSTMENT_SUBTRACT`, `REVERSAL`.
- `quantity`: Signed base-unit quantity (positive for inward, negative for outward).
- `base_unit`: Standard unit of measure (`TABLET`, `BOTTLE`, `ML`, etc.).
- `entered_quantity` / `entered_unit` / `conversion_factor`: Original user input and applied conversion factor.
- `source_document`: Audit link (`document_type`, `document_id`, `line_id`, `document_number`, `document_date`).
- `idempotency_key`: Client-supplied unique token preventing duplicate ledger movements.
- `is_inferred`: Boolean flag identifying inferred allocations (e.g., via FEFO).
- **Unique Constraint:** `(store_id, idempotency_key)`.

### 3. `stock_balances` (Derived Read Projection)
Derived cache for fast stock lookups:
- `store_id`, `product_id`, `batch_number`, `current_quantity`, `base_unit`, `last_transaction_id`, `updated_at`.
- **Unique Constraint:** `(store_id, product_id, batch_number)`.

### 4. `inventory_thresholds` (Store-Specific Reorder Rules)
Custom reorder points and safety stock levels configured per store and product:
- `store_id`: Store identifier.
- `product_id`: Catalogue product ID.
- `reorder_point`: Threshold at or below which reorder is triggered.
- `safety_stock_level`: Minimum safety buffer (strictly enforced: $\le$ `reorder_point`).
- `reorder_quantity`: Standard replenishment order batch size.
- `lead_time_days`: Supplier delivery lead time.
- `max_stock_level`: Optional maximum warehouse ceiling.
- `notes`: Pharmacist notes or distributor instructions.
- **Unique Constraint:** `(store_id, product_id)`.

### 5. `audit_sessions` (Physical Stock Audits & Cycle Counts)
Manages the structured lifecycle of store physical counts:
- `id`: Unique session identifier (UUID).
- `store_id`: Store identifier for isolation (indexed).
- `title`: Audit session title / designation.
- `audit_type`: `FULL_AUDIT` or `CYCLE_COUNT`.
- `status`: `DRAFT`, `IN_PROGRESS`, `COUNTING_COMPLETED`, `RECONCILED`, `CANCELLED`.
- `scope_product_ids`: Nullable list of product UUIDs for targeted cycle counts.
- `total_items_expected` / `total_items_counted`: Lot tracking metrics.
- `discrepancy_count` / `surplus_count` / `shortage_count`: Variance tally.
- `net_variance_value`: Total financial variance (positive for surplus, negative for shortage).
- `approved_by` / `reconciled_at`: Formal manager sign-off credentials.
- `notes`: Pharmacist notes or audit observations.

### 6. `audit_count_items` (Granular Lot Count Records)
Stores physical counts recorded per lot with unbiased blind sheet support:
- `id`: Count item identifier (UUID).
- `audit_session_id`: Foreign key referencing `audit_sessions.id`.
- `store_id`: Store identifier for isolation.
- `product_id`: Catalogue product reference.
- `batch_number`: Manufacturer lot number.
- `system_expected_quantity`: Book inventory quantity at session creation (masked when `blind=true`).
- `counted_quantity`: Physical verified count quantity.
- `variance_quantity`: $\text{counted\_quantity} - \text{system\_expected\_quantity}$.
- `unit_cost`: Batch purchase rate for valuation.
- `variance_value`: $\text{variance\_quantity} \times \text{unit\_cost}$.
- `discrepancy_reason`: `NORMAL_DISCREPANCY`, `DAMAGED_EXPIRED`, `UNRECORDED_RECEIPT`, `PILFERAGE_THEFT`, `DATA_ENTRY_ERROR`.
- `counted_by` / `counted_at`: Timestamp and audit trail of counting staff.

## API Endpoints

### Read APIs (Phase 3)
- `GET /api/v1/stores/{store_id}/inventory/connectivity`: Module route registration & live PostgreSQL ping.
- `GET /api/v1/stores/{store_id}/inventory`: Aggregated stock balances, base units, and earliest expiry.
- `GET /api/v1/stores/{store_id}/products/{product_id}/batches`: Product batches sorted by FEFO (`expiry_date ASC`).
- `GET /api/v1/stores/{store_id}/batches/{batch_id}`: Single batch details with store isolation.
- `GET /api/v1/stores/{store_id}/inventory/transactions`: Append-only transaction ledger (`created_at DESC`).
- `GET /api/v1/stores/{store_id}/inventory/summary`: Store KPI metrics (in-stock, active, expired, low-stock).

### Write APIs (Phase 4)
- `POST /api/v1/stores/{store_id}/batches`: Register new lot with unique constraint validation and initial inward ledger recording.
- `POST /api/v1/stores/{store_id}/inventory/movements`: Append-only stock movement with idempotency deduplication (`409`), negative stock prevention (`400`), automatic FEFO fallback for outward transactions without designated lots, atomic `$inc` on `batches`, and upsert on `stock_balances`.
- `POST /api/v1/stores/{store_id}/inventory/movements/reversal`: Audit-compliant compensating transaction reversal maintaining full immutable ledger history.

### Multi-Unit & FEFO Allocation APIs (Phase 5)
- `POST /api/v1/stores/{store_id}/inventory/conversions`: Packaging unit conversion calculation (`STRIP`, `BOX`, `BOTTLE`, etc.) with custom multiplier support.
- `POST /api/v1/stores/{store_id}/inventory/fefo-preview`: Non-mutating simulation of greedy FEFO batch consumption across active unexpired lots.
- `POST /api/v1/stores/{store_id}/inventory/fefo-dispense`: Outward sales dispense executing automated multi-lot FEFO deduction, atomic stock decrements, and immutable ledger logging (`is_inferred: True`).

### Expiry Risk & Waste Minimization APIs (Phase 6)
- `GET /api/v1/stores/{store_id}/inventory/expiry-buckets`: 5-tier classification (`EXPIRED`, `CRITICAL_30`, `NEAR_60`, `ATTENTION_90`, `SAFE`), aggregate at-risk capital valuation (cost & retail), and tier filtering (`?tier=`).
- `POST /api/v1/stores/{store_id}/batches/{batch_id}/segregate-expired`: Atomically quarantines expired stock (`current_quantity = 0`), rejects unexpired batches (`400 BATCH_NOT_EXPIRED`), and logs an append-only stock audit reduction (`ADJUSTMENT_SUBTRACT` with `STOCK_AUDIT`).
- `POST /api/v1/stores/{store_id}/batches/{batch_id}/return-to-supplier`: Executes vendor return for near-expiry or recalled stock, guards against overdrafts (`400 INSUFFICIENT_BATCH_STOCK`), records credit note details, and logs `RETURN_OUT` with `SUPPLIER_RETURN`.

### Low Stock Alerts & Reorder Thresholds APIs (Phase 7)
- `GET /api/v1/stores/{store_id}/inventory/low-stock-alerts`: 4-tier alert severity evaluation (`OUT_OF_STOCK`, `CRITICAL_LOW`, `REORDER_RECOMMENDED`, `ADEQUATE`), strictly excluding expired stock from safety stock buffers, with suggested replenishment math ($\max(\text{reorder\_qty}, \text{reorder\_point} \times 2 - \text{unexpired\_stock})$), recent purchase cost estimations, and severity/search query filtering.
- `POST /api/v1/stores/{store_id}/inventory/thresholds/{product_id}`: Store-specific threshold override upsert with validation guard (`safety_stock_level <= reorder_point`).
- `GET /api/v1/stores/{store_id}/inventory/thresholds/{product_id}`: Store-specific threshold retrieval with fallback to defaults.

### Physical Stock Audits & Discrepancy Reconciliation APIs (Phase 8)
- `POST /api/v1/stores/{store_id}/inventory/audits`: Initiates Full Store or scoped Cycle Count audit session.
- `GET /api/v1/stores/{store_id}/inventory/audits`: Lists store audit sessions with status and type query filters.
- `GET /api/v1/stores/{store_id}/inventory/audits/{audit_id}`: Retrieves session details and count items (strictly supports `?blind=true` parameter for unbiased floor sheets).
- `POST /api/v1/stores/{store_id}/inventory/audits/{audit_id}/counts`: Records physical counts, discovers unrecorded lots, computes batch variances, and advances status to `COUNTING_COMPLETED`.
- `GET /api/v1/stores/{store_id}/inventory/audits/{audit_id}/discrepancies`: Fetches financial variance report (Book Value, Counted Value, Net Variance) and surplus/shortage items.
- `POST /api/v1/stores/{store_id}/inventory/audits/{audit_id}/reconcile`: Authorizes reconciliation, enforces idempotency, and automatically posts compensating immutable ledger transactions (`ADJUSTMENT_ADD` / `ADJUSTMENT_SUBTRACT` with `source_document: STOCK_AUDIT`).
- `POST /api/v1/stores/{store_id}/inventory/audits/{audit_id}/cancel`: Safely cancels draft or in-progress audit session.

## Repeatable Database Scripts

- **Initialize PostgreSQL Schema & Seed Data:**
  ```powershell
  backend\.venv\Scripts\python scripts/init_postgres_tables.py
  ```

## Automated Tests

### Backend Pytest Suite (75 tests)
```powershell
backend\.venv\Scripts\python -m pytest -v
```
- `tests/test_health.py` (API health and database readiness)
- `tests/test_inventory_connectivity.py` (PostgreSQL connectivity, ping, error handling, credential masking)
- `tests/test_inventory_models.py` (Pydantic validation, sign enforcement, unique constraints)
- `tests/test_inventory_sql_relational.py` (SQLAlchemy relational constraints, store isolation, cascades)
- `tests/test_inventory_api.py` (Read APIs, FEFO batch sorting, pagination, store isolation)
- `tests/test_inventory_movements.py` (Write APIs, lot registration, overdraft rejection, idempotency, reversals)
- `tests/test_inventory_fefo_conversions.py` (Unit conversions, FEFO lot priority, multi-lot outward splits, overdraft guards)
- `tests/test_inventory_expiry_tracking.py` (5-tier risk classification, at-risk capital valuation, expired quarantine, unexpired guards, supplier returns)
- `tests/test_inventory_low_stock.py` (4-tier severity tiers, safety stock validation, expired stock exclusion, threshold overrides, suggested reorders, query filters, store isolation)
- `tests/test_inventory_audits.py` (Physical audits, scoped cycle counts, blind sheets, unrecorded lots, variance math, surplus/shortage ledger posting, idempotency guards, cancellation guards, store isolation)

### Frontend Flutter Test Suite (32 tests)
```powershell
C:\src\flutter\bin\flutter.bat test
```
- `test/widget_test.dart` (Dashboard UI smoke tests and drawer navigation)
- `test/inventory_service_test.dart` (Data models, HTTP service methods, live & fallback synchronization, unit conversions, FEFO allocation simulation, 5-tier expiry buckets, quarantine segregation, supplier returns, low stock alerts, threshold validation, Phase 8 physical audit models, blind count masking, variance math, and reconciliation posting)

## Security & Rules
- Database credentials must **never** be exposed in frontend code, client logs, or committed files.
- `.env` is excluded by `.gitignore`.
- All inventory mutations must remain store-scoped and authenticated.
- Blind count sheets strictly conceal expected quantities to enforce audit neutrality.
- Models are purely declarative schemas; instantiating a model never creates unintended stock movements.
- Outward movements exceeding available stock are strictly blocked with `400 Bad Request`.
- Client idempotency keys prevent duplicate transaction execution (`409 Conflict`).
- Reconciling audits is permanent and immutable, posting signed adjustment transactions to the stock ledger.


