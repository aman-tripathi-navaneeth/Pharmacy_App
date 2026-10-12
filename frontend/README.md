# Frontend workspace

The team has not selected a frontend framework in this starter, so this folder intentionally avoids committing to React Native, Flutter, or another tool. Add the agreed frontend application here and document its version, setup steps, lint/test commands, and build command in this file.

## Integration expectations
- Call the backend under `/api/v1` using a configurable API base URL.
- Never include `MONGODB_URL` or any Atlas secret in frontend/mobile environment files.
- Handle slow/failed networks, retries, loading/empty/error states, and duplicate submit prevention.
- Support Telugu and English labels and mobile-sized screens.
- For invoice/report OCR, show extracted values as editable drafts and require a clear review/confirm action before posting stock movements.
- Keep API types/contracts aligned with `docs/api-conventions.md`.
