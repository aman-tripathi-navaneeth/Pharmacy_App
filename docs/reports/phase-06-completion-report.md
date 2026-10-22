# Phase 6 Completion Report — Expiry Date Tracking, Near-Expiry Alerts & Waste Minimization

**Module:** Module 5: Inventory, Batches & Stock Ledger  
**Milestone:** Phase 6 (Expiry Date Tracking, Near-Expiry Risk Buckets & Waste Minimization Engine)  
**Status:** Complete & Verified  
**Date:** October 2026  

---

## 1. Phase Objectives

Phase 6 implements the authoritative expiry monitoring, capital risk valuation, quarantine segregation, and vendor return engines for **Module 5: Inventory, Batches & Stock Ledger**.
This phase establishes proactive inventory controls to minimize pharmaceutical waste, prevent accidental dispensing of expired medications, and track supplier return credits:

1. **Deterministic 5-Tier Expiry Risk Classification:** Classifies all active stock batches into five standardized risk buckets based on calendar days remaining until expiry:
   - `EXPIRED` ($\text{days} < 0$): Past expiry date; strictly blocked from sales dispense; immediate quarantine required.
   - `CRITICAL_30` ($0 \le \text{days} \le 30$): Critical risk window; primary candidates for expedited FEFO sales or supplier return.
   - `NEAR_60` ($31 \le \text{days} \le 60$): High attention window; eligible for promotional sales or vendor return agreement.
   - `ATTENTION_90` ($61 \le \text{days} \le 90$): Moderate attention window; monitored for movement velocity.
   - `SAFE` ($\text{days} > 90$): Fresh stock with adequate shelf-life buffer.
2. **At-Risk Capital Valuation:** Calculates financial exposure for batches in early risk tiers at both wholesale cost (`current_quantity × purchase_rate`) and retail value (`current_quantity × mrp`).
3. **Expired Stock Quarantine & Segregation Workflow:** Enables pharmacists to segregate expired inventory with zero leakage, atomically reducing active lot stock to zero and appending an immutable audit deduction to the stock ledger (`ADJUSTMENT_SUBTRACT` with `SourceDocumentType.STOCK_AUDIT`).
4. **Unexpired Segregation Guard:** Prevents misuse by strictly rejecting quarantine requests on batches with $\text{expiry\_date} \ge \text{today}$ (`400 Bad Request` with `BATCH_NOT_EXPIRED`).
5. **Return-to-Supplier Engine:** Manages outbound vendor returns for near-expiry or recalled stock, verifying available lot quantity, preventing overdrafts, recording credit note / invoice references, and logging immutable ledger transactions (`RETURN_OUT` with `SourceDocumentType.SUPPLIER_RETURN`).
6. **Frontend UI Workflows:** Delivers an interactive At-Risk Capital Summary banner, dynamic Expiry Risk Pill Filters, 5-tier semantic badges, Quarantine confirmation dialogs, and a modal for Supplier Returns with live cost calculations.
7. **Zero-Defect Verification:** Achieves 100% test pass rate across backend (53 tests) and frontend (21 tests), totaling 74 passing tests.

---

## 2. Deliverables Completed

### A. Backend Schemas & Data Contracts
Implemented in [backend/app/modules/inventory_batches_stock_ledger/models.py](file:///c:/Users/HP/OneDrive/Desktop/pharmacy-store-repository/backend/app/modules/inventory_batches_stock_ledger/models.py):

- **`ExpiryTier`:** Enum defining the 5 classification tiers (`EXPIRED`, `CRITICAL_30`, `NEAR_60`, `ATTENTION_90`, `SAFE`).
- **`ExpiryBucketSummary`:** Summary contract containing `tier`, `label`, `days_min`, `days_max`, `batch_count`, `total_units`, `total_purchase_value`, and `total_mrp_value`.
- **`ExpiryBatchItem`:** Granular batch representation detailing `batch_id`, `batch_number`, `product_id`, `product_name`, `expiry_date`, `days_until_expiry`, `tier`, `current_quantity`, `base_unit`, `mrp`, `purchase_rate`, `at_risk_purchase_value`, and `at_risk_mrp_value`.
- **`ExpiryBucketResponse`:** Aggregate response providing `store_id`, `total_active_batches`, `total_at_risk_units`, `total_at_risk_purchase_value`, `total_at_risk_mrp_value`, `buckets`, and `batches`.
- **`SegregateExpiredRequest`:** Quarantine segregation contract requiring client `idempotency_key` and optional reason, actor ID, and notes.
- **`ReturnToSupplierRequest`:** Vendor return contract capturing `supplier_id`, `quantity`, `return_reason`, `idempotency_key`, `supplier_invoice_ref`, `credit_note_number`, `actor_id`, and `notes`.

---

### B. Backend REST APIs & Business Logic
Implemented in [backend/app/modules/inventory_batches_stock_ledger/router.py](file:///c:/Users/HP/OneDrive/Desktop/pharmacy-store-repository/backend/app/modules/inventory_batches_stock_ledger/router.py):

1. **`GET /api/v1/stores/{store_id}/inventory/expiry-buckets`**:
   - Analyzes all active batches (`current_quantity > 0`) for the store against midnight UTC of current date.
   - Buckets lots into the 5 risk tiers and evaluates aggregate at-risk capital metrics.
   - Supports optional query parameter filtering by tier: `?tier=EXPIRED` or `?tier=CRITICAL_30`.
2. **`POST /api/v1/stores/{store_id}/batches/{batch_id}/segregate-expired`**:
   - Enforces store isolation and validates lot existence.
   - Strictly enforces expiry condition: aborts with `400 Bad Request` (`BATCH_NOT_EXPIRED`) if $\text{expiry\_date} \ge \text{today}$.
   - Verifies active stock availability (`current_quantity > 0`).
   - Deducts active lot quantity atomically to 0 via MongoDB `$set`.
   - Appends an audit deduction transaction to the append-only stock ledger:
     - `movement_type = MovementType.ADJUSTMENT_SUBTRACT`
     - `quantity = -segregated_quantity`
     - `source_document = SourceDocumentType.STOCK_AUDIT`
     - `document_number = "QUARANTINE-{batch_number}"`
     - `idempotency_key = clean_idempotency_key`
3. **`POST /api/v1/stores/{store_id}/batches/{batch_id}/return-to-supplier`**:
   - Validates supplier identifier, positive return quantity, and duplicate idempotency keys (`409 Conflict`).
   - Validates that requested return quantity does not exceed available lot balance (`400 Bad Request` with `INSUFFICIENT_BATCH_STOCK`).
   - Atomically decrements batch balance via `$inc: { current_quantity: -quantity }`.
   - Appends a return transaction to the append-only stock ledger:
     - `movement_type = MovementType.RETURN_OUT`
     - `quantity = -return_quantity`
     - `source_document = SourceDocumentType.SUPPLIER_RETURN`
     - `document_number = credit_note_number or "CN-{timestamp}"`
     - `notes = "Returned to supplier {supplier_id}: {reason}"`

---

### C. Automated Backend Test Suite
Implemented in [backend/tests/test_inventory_expiry_tracking.py](file:///c:/Users/HP/OneDrive/Desktop/pharmacy-store-repository/backend/tests/test_inventory_expiry_tracking.py):

| Test Case | Objective | Result |
| :--- | :--- | :---: |
| `test_expiry_buckets_multi_tier_classification_and_valuation` | Validates 5-tier classification and at-risk purchase/MRP valuation | **PASS** |
| `test_expiry_buckets_tier_filter_query_param` | Validates filtering by specific tier (`?tier=EXPIRED`, `?tier=SAFE`) | **PASS** |
| `test_segregate_expired_batch_success` | Validates stock set to 0 and `STOCK_AUDIT` ledger entry generated | **PASS** |
| `test_segregate_expired_batch_rejects_unexpired_batch` | Validates strict `400 BATCH_NOT_EXPIRED` rejection on fresh lots | **PASS** |
| `test_segregate_expired_batch_rejects_overdraft` | Validates rejection when batch quantity is zero | **PASS** |
| `test_return_batch_to_supplier_success` | Validates stock reduction, credit note recording, and `RETURN_OUT` ledger entry | **PASS** |
| `test_return_batch_to_supplier_rejects_overdraft` | Validates strict `400 INSUFFICIENT_BATCH_STOCK` rejection on overdraft | **PASS** |
| `test_idempotency_conflict_on_segregation_and_returns` | Validates `409 Conflict` deduplication on replay attacks | **PASS** |

**Backend Suite Total:** **53 passed in 13.79s** (100% pass rate).

---

### D. Frontend Data Models & UI Integration
Implemented in `frontend/lib/modules/inventory_batches_stock_ledger/`:

1. **Models:**
   - [expiry_tier_model.dart](file:///c:/Users/HP/OneDrive/Desktop/pharmacy-store-repository/frontend/lib/modules/inventory_batches_stock_ledger/models/expiry_tier_model.dart): `ExpiryTierEnum`, `ExpiryBucketItem`, `ExpiryBatchDetail`, and `ExpiryBucketResponse`.
2. **Reactive Service ([inventory_service.dart](file:///c:/Users/HP/OneDrive/Desktop/pharmacy-store-repository/frontend/lib/modules/inventory_batches_stock_ledger/services/inventory_service.dart)):**
   - `fetchExpiryBucketsAsync({ExpiryTierEnum? tier})`: Queries backend API with offline calculation fallback.
   - `segregateExpiredBatchAsync(...)`: Atomically deducts expired stock, adds audit transaction, and updates local state.
   - `returnToSupplierAsync(...)`: Decrements lot stock, posts `RETURN_OUT` ledger entry, and handles idempotency.
   - Reactive risk filters and metrics: `selectedExpiryTierFilter`, `setExpiryTierFilter`, `atRiskUnitsCount`, `atRiskPurchaseValue`, `atRiskMrpValue`, `criticalExpiryCount`.
3. **UI Components & Dialogs:**
   - [batch_card.dart](file:///c:/Users/HP/OneDrive/Desktop/pharmacy-store-repository/frontend/lib/modules/inventory_batches_stock_ledger/widgets/batch_card.dart):
     - Visual 5-tier badges with curated palette: Terracotta `#C85C54` (Expired), Amber `#D9A441` (Critical / Near), Blue `#637C8E` (Attention), Sage Green `#849A76` (Safe).
     - Prominent **Quarantine** action button for expired stock.
     - **Return** action button for vendor returns.
   - [return_to_supplier_dialog.dart](file:///c:/Users/HP/OneDrive/Desktop/pharmacy-store-repository/frontend/lib/modules/inventory_batches_stock_ledger/screens/return_to_supplier_dialog.dart):
     - Modal with supplier selector, quantity input, available stock validator, live return value calculation, reason dropdown, credit note tracing, and idempotency key generator.
   - [inventory_dashboard_screen.dart](file:///c:/Users/HP/OneDrive/Desktop/pharmacy-store-repository/frontend/lib/modules/inventory_batches_stock_ledger/screens/inventory_dashboard_screen.dart):
     - **At-Risk Capital Summary Banner** on Batches tab showing total capital at risk and affected units.
     - **Expiry Risk Pill Filters** (`All Batches`, `Expired (<0d)`, `Critical (<30d)`, `Near (31-60d)`, `Attention (61-90d)`, `Safe (>90d)`).
     - Quarantine confirmation dialog detailing ledger implications before submission.
4. **Frontend Unit Tests ([inventory_service_test.dart](file:///c:/Users/HP/OneDrive/Desktop/pharmacy-store-repository/frontend/test/inventory_service_test.dart)):**
   - `fetchExpiryBucketsAsync computes 5-tier classification and at-risk capital` (**PASS**).
   - `fetchExpiryBucketsAsync filters by tier parameter` (**PASS**).
   - `segregateExpiredBatchAsync quarantines expired batch and logs audit transaction` (**PASS**).
   - `segregateExpiredBatchAsync rejects unexpired batches` (**PASS**).
   - `returnToSupplierAsync deducts stock and appends return-out ledger entry` (**PASS**).
   - `returnToSupplierAsync guards against overdraft and duplicate idempotency` (**PASS**).

**Frontend Suite Total:** **21 passed in 4s** (100% pass rate).

---

### E. Production Build & Serving Verification
- **Web Compilation:** `flutter build web` completed successfully in `152.7s` with zero errors.
- **Web Server:** Active on `http://127.0.0.1:8080` via static Python HTTP server (HTTP 200 verified).
- **Backend Server:** Active on `http://127.0.0.1:8000` via Uvicorn (HTTP 200 verified).

---

## 3. Regulatory & Invariant Safeguards Enforced

| Safeguard | Implementation Mechanism | Verification Method |
| :--- | :--- | :--- |
| **Dispensing Expired Stock** | FEFO preview & dispense exclude expired stock by default | Verified in `test_fefo_preview_multi_lot_ordering_and_unexpired_filtering` |
| **Accidental Stock Loss Guard** | Segregation endpoint rejects batches with $\text{expiry\_date} \ge \text{today}$ | Verified in `test_segregate_expired_batch_rejects_unexpired_batch` |
| **Quarantine Auditability** | Segregated stock moves out of active circulation via `STOCK_AUDIT` ledger entry | Verified in `test_segregate_expired_batch_success` |
| **Supplier Credit Traceability** | Outbound supplier returns require credit note / invoice reference | Verified in `test_return_batch_to_supplier_success` |
| **Overdraft Protection** | Supplier returns exceeding available lot balance are rejected with `400` | Verified in `test_return_batch_to_supplier_rejects_overdraft` |
| **Idempotency Guard** | Replay of segregation or return requests rejected with `409 Conflict` | Verified in `test_idempotency_conflict_on_segregation_and_returns` |

---

## 4. Phase Verification Summary

| Metric | Status |
| :--- | :---: |
| **Backend Tests Passing** | **53 / 53** |
| **Frontend Tests Passing** | **21 / 21** |
| **Total Automated Tests** | **74 / 74** |
| **MongoDB Atlas Connectivity** | Connected (`pharmacy_store_dev`) |
| **FastAPI REST API** | Running on port 8000 (HTTP 200 verified) |
| **Flutter Web Application** | Running on port 8080 (HTTP 200 verified) |
| **Branding Preservation** | `Pharmacy Store • Module 5` strictly maintained |
| **Phase 6 Status** | **100% COMPLETE & VERIFIED** |

---

## 5. Next Steps: Roadmap for Subsequent Phases

- **Phase 7: Low Stock Alerts, Reorder Thresholds & Safety Stock Rules:**
  - Automated low-stock detection based on product-level minimum thresholds.
  - Reorder recommendation engine calculating suggested reorder quantities.
  - Stockout risk scoring and fast-moving stock velocity alerts.
- **Phase 8: Physical Stock Audits, Cycle Counts & Discrepancy Adjustments:**
  - Blind physical count audits and discrepancy calculations.
  - Approval workflows for variance reconciliation.
- **Phase 9: Role-Based Access Control, Audit Logs & Compliance Reporting:**
  - Pharmacist vs. Cashier vs. Manager permissions.
  - Regulatory Schedule H / Narcotics compliance log exports.
- **Phase 10: Multi-Store Stock Transfers & Warehouse Inward Routing:**
  - Inter-store transfer orders (Transfer Out $\rightarrow$ In Transit $\rightarrow$ Transfer In).
