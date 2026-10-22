# Frontend: Module 5 — Inventory, Batches & Stock Ledger

## Overview
This module implements the frontend UI, state management, and operational workflows for **Module 5: Inventory, Batches & Stock Ledger**.

## Architecture & File Structure
```
frontend/lib/modules/inventory_batches_stock_ledger/
├── models/
│   ├── enums.dart                   # MovementType, SourceDocumentType, UnitOfMeasure
│   ├── batch_model.dart             # BatchItem (FEFO sorting, expiry calculations)
│   ├── expiry_tier_model.dart       # ExpiryTierEnum (5-tier risk), ExpiryBucketItem, ExpiryBucketResponse
│   ├── low_stock_alert_model.dart   # StockAlertSeverityEnum (4 tiers), ProductThresholdConfigModel, LowStockAlertItemModel
│   ├── stock_transaction_model.dart # StockTransactionItem (Authoritative append-only ledger)
│   ├── stock_balance_model.dart     # StockBalanceItem (Derived fast projections, unexpiredQuantity, severity)
│   ├── unit_conversion_model.dart   # UnitConversionRequest, UnitConversionResult (Packaging math)
│   └── fefo_allocation_model.dart   # FefoBatchAllocation, FefoAllocationPreview, FefoDispenseResult
├── services/
│   └── inventory_service.dart       # Reactive state service, store isolation, packaging conversions, FEFO simulation, expiry risk buckets, low stock alerts & custom threshold overrides
├── screens/
│   ├── inventory_dashboard_screen.dart # Main screen with Balances, Batches (FEFO/Expiry Risk), and Ledger tabs
│   ├── add_batch_dialog.dart        # Register new lot modal with uppercase normalization & FEFO dates
│   ├── post_movement_dialog.dart    # Movement posting with packaging unit selector, live conversion & FEFO plan
│   ├── reorder_threshold_dialog.dart # Reorder point & safety stock configuration modal
│   └── return_to_supplier_dialog.dart # Outbound vendor return modal with credit note tracking & live valuation
└── widgets/
    ├── batch_card.dart              # Batch lot card with 5-tier expiry badges, Quarantine & Return actions
    ├── stock_balance_card.dart      # Product balance, severity badges, reorder threshold & configuration action
    ├── transaction_card.dart        # Authoritative append-only ledger audit trail card
    ├── movement_badge.dart          # Semantic color-coded badges for movements
    └── inventory_kpi_cards.dart     # Horizontal overview KPI stats
```

## Invariants & Design Principles Enforced
1. **Store Isolation:** All data operations, batch queries, and ledger transactions are strictly partitioned by `store_id` (switchable between stores via the header selector).
2. **FEFO Priority:** Batches are automatically ordered by earliest expiry date first (`#1 FEFO`, `#2 FEFO`), adhering to stock allocation rules.
3. **Packaging Conversions:** Standard pharmacy ratios (1 Strip = 10 Tablets, 1 Box = 100 Tablets / 10 Strips, 1 Bottle = 100 ML) and custom multipliers automatically convert entered quantities into canonical inventory units.
4. **FEFO Auto-Allocation:** Outward sales dispense requests without designated lots greedily allocate unexpired batches in chronological expiry order, previewing allocations and reporting shortages.
5. **5-Tier Expiry Date Risk Classification:** Batches are continuously classified into 5 distinct risk tiers:
   - `EXPIRED` (<0 days): Quarantine needed; cannot be dispensed.
   - `CRITICAL_30` (<30 days): High risk; priority for immediate sales or vendor return.
   - `NEAR_60` (31–60 days): Attention required; monitored for return agreements.
   - `ATTENTION_90` (61–90 days): Moderate buffer; stock rotation advised.
   - `SAFE` (>90 days): Optimal shelf-life stock.
6. **Quarantine Segregation:** Expired stock is isolated with zero inventory leakage, setting active stock to zero and appending an immutable audit adjustment (`ADJUSTMENT_SUBTRACT` with `STOCK_AUDIT`). Unexpired stock is protected from segregation.
7. **Vendor Return Traceability:** Outbound returns to suppliers decrement batch quantities, record credit note and supplier invoice references, and post `RETURN_OUT` ledger entries. Overdrafts are strictly prevented.
8. **4-Tier Stock Alert Severity Classification:** Dynamically monitors unexpired stock levels against reorder thresholds:
   - `OUT_OF_STOCK`: Unexpired stock $\le 0$.
   - `CRITICAL_LOW`: $0 < \text{unexpired\_stock} \le \text{safety\_stock\_level}$.
   - `REORDER_RECOMMENDED`: $\text{safety\_stock\_level} < \text{unexpired\_stock} \le \text{reorder\_point}$.
   - `ADEQUATE`: $\text{unexpired\_stock} > \text{reorder\_point}$.
9. **Regulatory Expired Stock Exclusion:** When evaluating safety stock and replenishment triggers, expired lots are strictly excluded. Expired stock cannot satisfy reorder or safety buffers.
10. **Store-Specific Threshold Overrides:** Pharmacists configure `reorder_point`, `safety_stock_level`, `reorder_quantity`, `lead_time_days`, and `max_stock_level` per product with strict invariant enforcement ($\text{safety\_stock\_level} \le \text{reorder\_point}$).
11. **Replenishment Recommendation Engine:** Automatically calculates suggested replenishment quantities ($\max(\text{reorder\_qty}, \text{reorder\_point} \times 2 - \text{unexpired\_stock})$) and estimated reorder costs.
12. **Signed Movement Invariants:**
    - Inward movements (`PURCHASE_IN`, `RETURN_IN`, `ADJUSTMENT_ADD`) enforce positive quantities (`+`).
    - Outward movements (`SALES_REPORT_OUT`, `RETURN_OUT`, `ADJUSTMENT_SUBTRACT`) enforce negative quantities (`-`).
    - Zero quantity movements are rejected.
13. **Authoritative Ledger:** Balance projections are strictly derived from active batches and append-only ledger transactions. Transactions cannot be deleted; adjustments are posted as new entries. System-inferred lot deductions are tagged with `is_inferred: True`.
14. **Idempotency Keys:** Every manual adjustment, inward posting, FEFO dispense, segregation, vendor return, and threshold update generates a unique idempotency key (`IDEM-...`) to prevent duplicate transactions.
15. **Responsive Sliver Architecture:** Uses `CustomScrollView` with slivers to ensure that banners, filter chips, and card lists scroll fluidly together with zero `RenderFlex` overflow errors across all mobile, tablet, and desktop viewports.
16. **Figma Palette & Typography:** Primary Sage Green (`#849A76`), Warm Linen Cream (`#F5F1E9`), Soft Cream Cards (`#F8F5EE`, 12px corners, subtle borders `#E8E3D8`), Dark Brown typography (`#493A2B`), Muted Taupe (`#857667`), Warm Amber (`#D9A441`), and Terracotta (`#C85C54`).
17. **Integration Boundaries:** Coordinates with Module 1 (Auth/Store), Module 2 (Catalogue), Module 4 (Invoices), Module 6 (Expiry), Module 7 (Sales), and Module 12 (Offline Sync).
