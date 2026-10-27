# Expiry, Low Stock & Reconciliation Module (M6)

## Overview

This module provides read-only inventory expiry monitoring, low-stock alerts based on configured thresholds, and an explicit service-unavailable response for reconciliation until the shared inventory movement service is integrated.

**Safety:** The current reconciliation endpoint does not modify stock. Store-level authorization must be integrated before production use.

## API Endpoints

All paths below are relative to the API root.

### Expiry

- `GET /api/v1/stores/{store_id}/inventory/expiry`
  - Lists batches with expiry information.
  - Supports status filtering, product/batch search, and pagination.
  - Status values: `EXPIRED`, `CRITICAL`, `WARNING`, `OK`, `NO_EXPIRY`.

- `GET /api/v1/stores/{store_id}/inventory/expiry/summary`
  - Returns counts grouped by expiry status.

### Low Stock

- `GET /api/v1/stores/{store_id}/inventory/low-stock`
  - Lists products at or below their configured reorder threshold.
  - Supports product-name search and pagination.
  - Thresholds can be configured through supported product fields or `stock_settings.low_stock_thresholds`.
  - Quantities and thresholds are expressed in base units.

- `GET /api/v1/stores/{store_id}/inventory/low-stock/summary`
  - Returns a summary of detected low-stock and out-of-stock products.

### Reconciliation

- `GET /api/v1/stores/{store_id}/inventory/reconciliation`
  - Currently returns HTTP `503` with code `INVENTORY_SERVICE_UNAVAILABLE`.
  - Reconciliation is unavailable until the shared inventory movement service is implemented.
  - This endpoint does not change stock.

## Error Handling

The module uses structured error details for conditions such as:

- `DATABASE_NOT_CONFIGURED` — database is unavailable to the application.
- `INVALID_EXPIRY_STATUS` — an unsupported expiry status was supplied.
- `INVALID_EXPIRY_SETTINGS` — configured expiry thresholds are inconsistent.
- `INVENTORY_SERVICE_UNAVAILABLE` — reconciliation is not implemented.

## Testing

Run the module's backend test suite from the `backend` directory:

```powershell
.\.venv\Scripts\python.exe -m pytest -q
```

Tests cover expiry summaries, status filtering, search, pagination, invalid status handling, low-stock thresholds, missing database configuration, and reconciliation's unavailable response.

## Outstanding Work

1. Integrate and enforce server-side store-level authentication and authorization on all endpoints.
2. Integrate reconciliation with the shared inventory movement service.
3. Verify the implementation against the agreed inventory schema and integration tests before production deployment.
4. Review the Starlette/httpx deprecation warning separately from functional test results.