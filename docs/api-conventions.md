# API conventions

- Prefix application routes with `/api/v1`.
- Use JSON request/response bodies and plural resource names where practical.
- Scope store data under `/stores/{store_id}/...`; server-side authorization must verify the signed-in user can access that store.
- Validate request fields and base units on the backend; do not trust frontend-only validation.
- Use consistent status codes: `200` for successful reads/updates, `201` for created resources, `202` when work is accepted for later processing, `400` for invalid workflow/input, `401` unauthenticated, `403` unauthorized, `404` missing resource, `409` conflict/duplicate, `422` schema validation, and `500` unexpected server errors.
- Use an idempotency key for retryable create/confirm operations that must not be applied twice. Persist enough information to return or identify the previous result.
- Return a stable error shape, e.g. `{"detail":"Human-readable explanation","code":"STABLE_ERROR_CODE"}`.
- Document pagination, sorting, units, timezone/date handling, and whether a quantity is inferred or user-confirmed.
- Never return secrets, internal stack traces, or another store's data.
