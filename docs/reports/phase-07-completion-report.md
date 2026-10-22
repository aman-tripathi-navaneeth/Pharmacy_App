# Phase 7 Completion Report — Low Stock Alerts, Reorder Thresholds & Safety Stock Rules

**Module:** Module 5: Inventory, Batches & Stock Ledger  
**Milestone:** Phase 7 (Low Stock Alerts, Reorder Thresholds & Safety Stock Rules Engine)  
**Status:** Complete & Verified  
**Date:** October 2026  

---

## 1. Phase Objectives

Phase 7 implements the authoritative inventory replenishment intelligence, stockout prevention, reorder threshold configuration, and safety stock evaluation engine for **Module 5: Inventory, Batches & Stock Ledger**.
This phase establishes proactive operational safeguards ensuring that pharmacy stores maintain adequate medicine availability, prevent drug shortages, and accurately calculate replenishment orders:

1. **Deterministic 4-Tier Stock Alert Severity Classification:** Classifies all catalogue medicines dynamically based on their current unexpired stock balance against product thresholds:
   - `OUT_OF_STOCK` ($\text{unexpired\_stock} \le 0$): Medicine is completely unavailable for dispensing; emergency reorder required.
   - `CRITICAL_LOW` ($0 < \text{unexpired\_stock} \le \text{safety\_stock\_level}$): Stock has breached the safety buffer; immediate replenishment required to prevent stockout.
   - `REORDER_RECOMMENDED` ($\text{safety\_stock\_level} < \text{unexpired\_stock} \le \text{reorder\_point}$): Stock has fallen to or below the reorder point; standard purchase order recommended.
   - `ADEQUATE` ($\text{unexpired\_stock} > \text{reorder\_point}$): Inventory levels are healthy and sufficient.
2. **Regulatory Safeguard (Expired Stock Exclusion):** Under pharmacy regulations, expired medication cannot be dispensed. When computing $\text{current\_unexpired\_stock}$, lots with $\text{expiry\_date} < \text{today}$ are strictly excluded from safety stock evaluation. Even if a pharmacy holds hundreds of expired units physically in stock, if unexpired stock is below the safety threshold, the product triggers `CRITICAL_LOW` or `OUT_OF_STOCK`.
3. **Store-Specific Threshold Overrides:** Pharmacists and store managers can configure custom thresholds per store and product (`reorder_point`, `safety_stock_level`, `reorder_quantity`, `lead_time_days`, `max_stock_level`, and `notes`), stored in the dedicated `inventory_thresholds` collection.
4. **Safety Stock Validation Guard:** Strictly enforces the invariant $\text{safety\_stock\_level} \le \text{reorder\_point}$. Requests violating this rule are rejected with `422 Unprocessable Entity` or `400 Bad Request`.
5. **Replenishment Recommendation Engine:** Automatically calculates suggested replenishment quantities and financial cost estimates:
   $$\text{suggested\_reorder\_quantity} = \max(\text{reorder\_quantity}, (\text{reorder\_point} \times 2) - \text{current\_unexpired\_stock})$$
   $$\text{estimated\_reorder\_cost} = \text{suggested\_reorder\_quantity} \times \text{recent\_purchase\_rate}$$
6. **Frontend UI Workflows:** Delivers an interactive Low Stock Alert Banner on the Balances tab, dynamic Severity Pill Filter Chips (`All Items`, `Out of Stock`, `Critical Low`, `Reorder Required`, `Adequate Stock`), color-coded severity badges on `StockBalanceCard`, and a `ReorderThresholdDialog` modal for live threshold configuration.
7. **Zero-Defect Verification:** Achieves 100% test pass rate across backend (62 tests) and frontend (27 tests), totaling 89 passing automated tests.

---

## 2. Deliverables Completed

### A. Backend Schemas & Data Contracts
Implemented in [backend/app/modules/inventory_batches_stock_ledger/models.py](file:///c:/Users/HP/OneDrive/Desktop/pharmacy-store-repository/backend/app/modules/inventory_batches_stock_ledger/models.py):

- **`StockAlertSeverity`:** Enum defining the 4 severity tiers (`OUT_OF_STOCK`, `CRITICAL_LOW`, `REORDER_RECOMMENDED`, `ADEQUATE`).
- **`ProductThresholdConfig`:** MongoDB collection document model for `inventory_thresholds` storing `store_id`, `product_id`, `reorder_point`, `safety_stock_level`, `reorder_quantity`, `lead_time_days`, `max_stock_level`, `notes`, `created_at`, and `updated_at`.
- **`UpdateThresholdsRequest`:** Request contract for setting or updating product thresholds with Pydantic validator enforcing `safety_stock_level <= reorder_point`.
- **`LowStockAlertItem`:** Granular alert representation detailing `product_id`, `product_name`, `category`, `base_unit`, `current_unexpired_stock`, `expired_stock`, `total_stock`, `safety_stock_level`, `reorder_point`, `reorder_quantity`, `lead_time_days`, `severity`, `suggested_reorder_quantity`, `estimated_unit_cost`, `estimated_reorder_cost`, `active_batch_count`, and `earliest_expiry_date`.
- **`LowStockAlertsResponse`:** Aggregate response providing `store_id`, `total_monitored_products`, `out_of_stock_count`, `critical_low_count`, `reorder_recommended_count`, `adequate_count`, `total_estimated_reorder_cost`, and `alerts`.

---

### B. Database Indexing
Implemented in [backend/app/modules/inventory_batches_stock_ledger/indexes.py](file:///c:/Users/HP/OneDrive/Desktop/pharmacy-store-repository/backend/app/modules/inventory_batches_stock_ledger/indexes.py):

- Added unique compound index on `inventory_thresholds`:
  ```python
  IndexModel(
      [("store_id", ASCENDING), ("product_id", ASCENDING)],
      unique=True,
      name="idx_inventory_thresholds_store_product_unique",
  )
  ```

---

### C. Backend REST APIs & Business Logic
Implemented in [backend/app/modules/inventory_batches_stock_ledger/router.py](file:///c:/Users/HP/OneDrive/Desktop/pharmacy-store-repository/backend/app/modules/inventory_batches_stock_ledger/router.py):

1. **`GET /api/v1/stores/{store_id}/inventory/low-stock-alerts`**:
   - Aggregates unexpired vs. expired stock across active batches for each product.
   - Merges custom threshold overrides from `inventory_thresholds` (or falls back to product defaults).
   - Evaluates severity tiers strictly based on `current_unexpired_stock`.
   - Computes suggested reorder quantity and estimated procurement cost using recent lot purchase rates.
   - Supports query filtering by severity (`?severity=CRITICAL_LOW`) and search term (`?search=dolo`).
   - Sorts alerts in descending order of operational priority (`OUT_OF_STOCK` $\rightarrow$ `CRITICAL_LOW` $\rightarrow$ `REORDER_RECOMMENDED` $\rightarrow$ `ADEQUATE`).
2. **`POST /api/v1/stores/{store_id}/inventory/thresholds/{product_id}`**:
   - Validates that `safety_stock_level <= reorder_point`.
   - Upserts product threshold configuration atomically via MongoDB `$set` with `upsert=True`.
   - Updates `updated_at` timestamp.
3. **`GET /api/v1/stores/{store_id}/inventory/thresholds/{product_id}`**:
   - Returns store-specific threshold override or computes default thresholds (default threshold, safety stock at 40%, reorder qty = 100).

---

### D. Automated Backend Test Suite
Implemented in [backend/tests/test_inventory_low_stock.py](file:///c:/Users/HP/OneDrive/Desktop/pharmacy-store-repository/backend/tests/test_inventory_low_stock.py):

| Test Case | Objective | Result |
| :--- | :--- | :---: |
| `test_threshold_override_persistence_and_retrieval` | Validates upsert and retrieval of custom thresholds | **PASS** |
| `test_threshold_validation_rejects_safety_greater_than_reorder` | Validates strict `422/400` rejection when `safety > reorder` | **PASS** |
| `test_low_stock_severity_out_of_stock` | Validates `OUT_OF_STOCK` classification when unexpired stock is 0 | **PASS** |
| `test_low_stock_severity_critical_low` | Validates `CRITICAL_LOW` classification when unexpired $\le$ safety stock | **PASS** |
| `test_low_stock_severity_reorder_recommended` | Validates `REORDER_RECOMMENDED` when unexpired $\le$ reorder point | **PASS** |
| `test_low_stock_severity_adequate` | Validates `ADEQUATE` classification when unexpired $>$ reorder point | **PASS** |
| `test_expired_stock_excluded_from_safety_thresholds` | Validates that expired stock does not mask a stockout or critical low | **PASS** |
| `test_low_stock_severity_and_search_query_filters` | Validates filtering by severity parameter and search keyword | **PASS** |
| `test_low_stock_store_isolation` | Validates strict store data isolation between STR-001 and STR-002 | **PASS** |

**Backend Suite Total:** **62 passed in 16.98s** (100% pass rate).

---

### E. Frontend Data Models & UI Integration
Implemented in `frontend/lib/modules/inventory_batches_stock_ledger/`:

1. **Models:**
   - [low_stock_alert_model.dart](file:///c:/Users/HP/OneDrive/Desktop/pharmacy-store-repository/frontend/lib/modules/inventory_batches_stock_ledger/models/low_stock_alert_model.dart): `StockAlertSeverityEnum`, `ProductThresholdConfigModel`, `LowStockAlertItemModel`, and `LowStockAlertsResponseModel`.
   - [stock_balance_model.dart](file:///c:/Users/HP/OneDrive/Desktop/pharmacy-store-repository/frontend/lib/modules/inventory_batches_stock_ledger/models/stock_balance_model.dart): Extended with `unexpiredQuantity`, `safetyStockLevel`, and `severity`.
2. **Reactive Service ([inventory_service.dart](file:///c:/Users/HP/OneDrive/Desktop/pharmacy-store-repository/frontend/lib/modules/inventory_batches_stock_ledger/services/inventory_service.dart)):**
   - `fetchLowStockAlertsAsync({StockAlertSeverityEnum? severity, String? search})`: Queries backend API with local offline calculation fallback.
   - `updateProductThresholdsAsync(...)`: Upserts thresholds live via HTTP or persists to local cache; validates `safety <= reorder`.
   - `fetchProductThresholdAsync(productId)`: Retrieves threshold configuration.
   - Getters: `selectedStockAlertSeverityFilter`, `outOfStockProductsCount`, `lowStockProductsCount`.
3. **UI Components & Dialogs:**
   - [reorder_threshold_dialog.dart](file:///c:/Users/HP/OneDrive/Desktop/pharmacy-store-repository/frontend/lib/modules/inventory_batches_stock_ledger/screens/reorder_threshold_dialog.dart):
     - Modal for configuring Reorder Point, Safety Stock Level, Reorder Quantity, Lead Time (Days), Max Stock Level, and notes.
     - Live client-side validation ensuring safety stock does not exceed reorder point.
   - [stock_balance_card.dart](file:///c:/Users/HP/OneDrive/Desktop/pharmacy-store-repository/frontend/lib/modules/inventory_batches_stock_ledger/widgets/stock_balance_card.dart):
     - Severity badges (`OUT OF STOCK`, `CRITICAL`, `REORDER`, `IN STOCK`) with curated Figma palette colors.
     - Prominent **Thresholds** button opening `ReorderThresholdDialog`.
   - [inventory_dashboard_screen.dart](file:///c:/Users/HP/OneDrive/Desktop/pharmacy-store-repository/frontend/lib/modules/inventory_batches_stock_ledger/screens/inventory_dashboard_screen.dart):
     - Upgraded Balances tab to use `CustomScrollView` with slivers to guarantee zero `RenderFlex` overflow across all viewport sizes.
     - **Low Stock & Replenishment Alert Banner** displaying out-of-stock and reorder alert counts.
     - **Severity Pill Filter Chips** (`All Items`, `Out of Stock (0)`, `Critical Low (<= Safety)`, `Reorder Required`, `Adequate Stock`).
4. **Frontend Unit Tests ([inventory_service_test.dart](file:///c:/Users/HP/OneDrive/Desktop/pharmacy-store-repository/frontend/test/inventory_service_test.dart)):**
   - `Phase 7: Dynamic StockAlertSeverity classification based on unexpired stock vs thresholds` (**PASS**).
   - `Phase 7: Expired stock is excluded from unexpired stock balance calculations` (**PASS**).
   - `Phase 7: updateProductThresholdsAsync validates safety_stock <= reorder_point` (**PASS**).
   - `Phase 7: Custom threshold overrides persist and dynamically alter balance severity` (**PASS**).
   - `Phase 7: Severity filter accurately filters currentStoreBalances` (**PASS**).
   - `Phase 7: fetchLowStockAlertsAsync calculates replenishment recommendations` (**PASS**).

**Frontend Suite Total:** **27 passed in 4s** (100% pass rate).

---

### F. Production Web Build & Server Verification
- **Web Compilation:** `flutter build web` completed successfully in `142.0s` with zero errors.
- **Web Server:** Active on `http://127.0.0.1:8080` via static Python HTTP server (verified).
- **Backend Server:** Active on `http://127.0.0.1:8000` via Uvicorn daemon; `/health` returned `status: ok` and live `/api/v1/stores/STR-001/inventory/low-stock-alerts` endpoint verified.

---

## 3. Regulatory & Invariant Safeguards Enforced

| Safeguard | Implementation Mechanism | Verification Method |
| :--- | :--- | :--- |
| **Expired Stock Masking Guard** | Expired lots are strictly excluded when evaluating unexpired stock for safety thresholds | Verified in `test_expired_stock_excluded_from_safety_thresholds` |
| **Safety vs. Reorder Constraint** | Enforces $\text{safety\_stock\_level} \le \text{reorder\_point}$ in Pydantic & route handlers | Verified in `test_threshold_validation_rejects_safety_greater_than_reorder` |
| **Store Data Isolation** | Threshold configs and alerts are strictly partitioned by `store_id` | Verified in `test_low_stock_store_isolation` |
| **Suggested Reorder Calculation** | Math enforces $\max(\text{reorder\_qty}, \text{reorder\_point} \times 2 - \text{unexpired\_stock})$ | Verified in `test_low_stock_severity_out_of_stock` |
| **Compound Index Integrity** | Unique compound index on `("store_id", "product_id")` prevents duplicates | Verified in `test_index_definitions_structure` |
| **Responsive Viewport Safety** | `CustomScrollView` slivers guarantee no `RenderFlex` overflow even in compact viewports | Verified in Flutter `widget_test.dart` and `flutter test` |

---

## 4. Phase Verification Summary

| Metric | Status |
| :--- | :---: |
| **Backend Tests Passing** | **62 / 62** |
| **Frontend Tests Passing** | **27 / 27** |
| **Total Automated Tests** | **89 / 89** |
| **MongoDB Atlas Connectivity** | Connected (`pharmacy_store_dev`) |
| **FastAPI REST API** | Running on port 8000 (HTTP 200 verified) |
| **Flutter Web Application** | Running on port 8080 (HTTP 200 verified) |
| **Branding Preservation** | `Pharmacy Store • Module 5` strictly maintained |
| **Phase 7 Status** | **100% COMPLETE & VERIFIED** |

---

## 5. Next Steps: Roadmap for Subsequent Phases

- **Phase 8: Physical Stock Audits, Cycle Counts & Discrepancy Adjustments:**
  - Blind physical count audit sessions (Store, Category, or Full Count).
  - Count sheet generation and blind entry by pharmacy technicians.
  - Discrepancy reconciliation engine (Expected System Stock vs. Actual Physical Stock).
  - Approval workflows for variance reconciliation with automated `ADJUSTMENT_ADD` / `ADJUSTMENT_SUBTRACT` ledger entries tagged with `STOCK_AUDIT`.
- **Phase 9: Role-Based Access Control, Audit Logs & Compliance Reporting:**
  - Pharmacist vs. Cashier vs. Store Manager permissions.
  - Regulatory Schedule H / Narcotics compliance log exports.
- **Phase 10: Multi-Store Stock Transfers & Warehouse Inward Routing:**
  - Inter-store transfer orders (Transfer Out $\rightarrow$ In Transit $\rightarrow$ Transfer In).
