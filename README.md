# Pharmacy Store Application — Team Repository

Shared starter repository for the 12-module Pharmacy Store Application. It establishes conventions and a minimal API scaffold; it is **not** the finished application.

## Product principles
- Mobile-first, practical for small/rural medical shops; support Telugu and English in the product UI.
- The Inventory, Batches & Stock Ledger is the source of truth for stock. All stock changes must be recorded through controlled ledger movements.
- Purchase-invoice OCR and end-of-day sales-report OCR create **drafts**. Stock changes only after a user reviews and confirms the document.
- Duplicate report submissions/retries must not apply the same movement twice.
- Do not put MongoDB credentials in frontend/mobile code. Only the backend connects to Atlas.
- Never silently delete posted stock movements; use a reversal or adjustment with an audit trail.

## Repository layout
```text
backend/        FastAPI API scaffold, shared configuration, module packages and tests
frontend/       Framework-neutral starting notes; add the team's chosen frontend here
docs/           Architecture, API conventions, module ownership and data rules
.github/        Pull request and issue templates
```

## Get started (backend)
Requires Python 3.11+ (use the version selected by the team if already standardized).

1. Create and activate a virtual environment in `backend/`.
2. Install dependencies: `pip install -r requirements.txt`.
3. Copy the root `.env.example` to `backend/.env` and set `MONGODB_URL` and `MONGODB_DATABASE` if you want to test Atlas connectivity.
4. From `backend/`, run `uvicorn app.main:app --reload`.
5. Open `http://127.0.0.1:8000/docs`; check `http://127.0.0.1:8000/health` and `http://127.0.0.1:8000/ready`.
6. Run `pytest` from `backend/`.

The `/health` endpoint only verifies the API process. `/ready` reports whether the configured database can be reached. The API can start without a configured database to allow local scaffold work; database-dependent functionality will not work until Atlas is configured.

## Team workflow
- Create one branch per task/module: `feature/<module-short-name>` or `fix/<issue-short-name>`.
- Open a pull request; explain the change, tests run, API/schema changes, and screenshots when applicable.
- Do not push directly to `main`; enable branch protection and at least one review in GitHub repository settings.
- Keep pull requests focused. Avoid editing another module's files without coordinating with that module's owner.
- Discuss shared API contracts and database changes before implementation. Do not independently change common conventions.
- Never commit `.env`, access tokens, patient/customer data, database dumps, or real invoices.

## Important docs
- [Architecture](docs/architecture.md)
- [Module ownership](docs/team-module-map.md)
- [API conventions](docs/api-conventions.md)
- [Data and stock-ledger rules](docs/data-and-stock-rules.md)
- [Frontend starting notes](frontend/README.md)

## Before calling a module complete
- The feature works from UI through API to database.
- Validation and permission checks are server-side.
- Relevant tests pass; failure paths and retries have been tested.
- Duplicate requests cannot create duplicate financial/stock effects.
- No secrets or real customer/store data are included in commits.
- API and setup documentation are updated.
