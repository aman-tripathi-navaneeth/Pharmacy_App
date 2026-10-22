# Frontend Modules Directory Structure

This directory divides the Flutter mobile application into 12 discrete modules according to `docs/team-module-map.md`. Each module team member owns their corresponding directory.

| # | Directory | Module Name | Assigned Member | Implementation Status |
|---|---|---|---|---|
| 1 | `authentication_store_roles` | Authentication, Store Setup & User Roles | Member 1 | Scaffolded Boundary |
| 2 | `catalogue_search_units` | Medicine Catalogue, Search & Units | Member 2 | Scaffolded Boundary |
| 3 | `suppliers_purchase_orders` | Supplier & Purchase Orders | Member 3 | Scaffolded Boundary |
| 4 | `purchase_invoice_scanning` | Purchase Invoice Scanning & Inward | Member 4 | Scaffolded Boundary |
| **5** | **`inventory_batches_stock_ledger`** | **Inventory, Batches & Stock Ledger** | **Member 5 (Us)** | **Complete Production Design** |
| 6 | `expiry_low_stock_reconciliation` | Expiry, Low Stock & Reconciliation | Member 6 | Scaffolded Boundary |
| 7 | `outward_sales_report_scanning` | Outward Sales Report Scanning | Member 7 | Scaffolded Boundary |
| 8 | `customers_refills_prescriptions` | Customers, Refills & Prescriptions | Member 8 | Scaffolded Boundary |
| 9 | `udhaar_credit_payments` | Udhaar / Credit & Payments | Member 9 | Scaffolded Boundary |
| 10 | `whatsapp_notifications` | WhatsApp & Notifications | Member 10 | Scaffolded Boundary |
| 11 | `today_dashboard_reports` | Today Dashboard & Reports | Member 11 | Scaffolded Boundary |
| 12 | `offline_sync_reliability` | Offline Sync, Integration & Reliability | Member 12 | Scaffolded Boundary |

## Guidelines
- Shared components, wrappers, and theme tokens reside in `frontend/lib/core/`.
- Cross-module contracts must use clear interfaces and avoid direct mutations of another module's internal state.
- Module 5 is the authoritative owner for batches, stock balances, and the append-only stock ledger.
