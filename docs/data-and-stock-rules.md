# Data and stock rules

## Suggested tables
Names below are conceptual; each becomes a real table in an Alembic migration owned
by the responsible module (see docs/architecture.md for module data boundaries).
- `stores`, `users`, `memberships`: store identity and access relationships (coordinate with authentication module).
- `products`: catalogue-level medicine identity and base-unit definitions.
- `batches`: product/store-specific batch or lot, expiry, purchase cost where permitted, and batch quantity metadata.
- `stock_transactions`: append-only posted movement records, including store, product, batch when known, signed base-unit quantity, movement type, source document/line, actor, timestamps, idempotency key, and audit metadata.
- `stock_balances`: optional projection/cache for fast reads; not a substitute for the ledger.
- `purchases`, `purchase_items`, `sales_reports`, `sales_report_lines`: source documents and reviewed line items. Final names/schema should be agreed by affected module owners before implementation.

## Invariants
1. All stock-affecting workflows use a single validated inventory movement service.
2. Quantities are converted to a defined base unit before posting. Store entered quantity and unit too when useful for auditability.
3. A purchase invoice or end-of-day sales report is a draft until a user confirms it. OCR alone never changes stock.
4. The same confirmed source line cannot be posted twice, even after client/network retries.
5. Posted ledger transactions are not silently edited or deleted. Correct errors with a reversal/adjustment that references the original transaction.
6. If batch detail is absent from a sales report, any inferred batch allocation must be marked as inferred. FEFO may be used if agreed by the team, but its choice must remain auditable.
7. Do not oversell or allow negative batches unless the team explicitly defines and approves that business rule.
8. Use suitable unique indexes for idempotency and frequently queried store/product/batch fields. Verify index definitions against actual schemas before deployment.
9. Store IDs and ownership must be checked server-side in every read and write.
