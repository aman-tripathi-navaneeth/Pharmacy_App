# Team module map (12 members)

Each member owns the frontend, backend, data operations, and tests for the assigned module. Shared conventions and cross-module contracts must still be coordinated.

| Member | Module | Main scope |
|---:|---|---|
| 1 | Authentication, Store Setup & User Roles | Sign-in, store profile, user roles, access checks |
| 2 | Medicine Catalogue, Search & Units | Medicine/product records, synonyms, units and conversions |
| 3 | Supplier & Purchase Orders | Supplier records and purchase-order lifecycle |
| 4 | Purchase Invoice Scanning & Inward | Invoice capture/OCR, review, confirmation and inward integration |
| 5 | Inventory, Batches & Stock Ledger | Batch quantities, movement ledger, stock views and reconciliation |
| 6 | Expiry, Low Stock & Reconciliation | Alerts, thresholds, expiry monitoring and count variance workflow |
| 7 | Outward Sales Report Scanning | End-of-day report capture/OCR, review and confirmed stock-out movements |
| 8 | Customers, Refills & Prescriptions | Customer records, refill tracking and prescription-related workflows |
| 9 | Udhaar / Credit & Payments | Credit balances, payment recording and history |
| 10 | WhatsApp & Notifications | Approved message templates, reminders and notification delivery |
| 11 | Today Dashboard & Reports | Daily summary cards and operational reports |
| 12 | Offline Sync, Integration & Reliability | Queues, retry behavior, conflict resolution and integration tests |

## Integration checkpoints
- Agree on API paths, payloads, error formats, and store scoping before parallel implementation.
- Purchase inward and sales report confirmation must call the inventory movement service; they must not edit balances independently.
- Every retryable write needs an idempotency strategy.
- Coordinate shared-file changes through a small reviewed PR, rather than simultaneous conflicting edits.
