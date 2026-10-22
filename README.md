# Pharmacy Store Application

The project has two application folders: `backend` (FastAPI) and `frontend` (Flutter). The backend uses PostgreSQL as its only database.

## Requirements

- Python 3.11 or later
- PostgreSQL 13 or later
- Flutter/Dart versions allowed by `frontend/pubspec.yaml`
- Chrome, Windows desktop, or an Android emulator/device
- Tesseract OCR installed on the backend host for bill-image OCR

## Configure PostgreSQL

1. Start the local PostgreSQL service. If it is already listening on port 5432, do not start a second server.
2. Create `medishop_dev` only if it does not already exist. Do not drop or recreate a database that contains application data.
3. Copy `backend/.env.example` to `backend/.env` if a local env file does not already exist. Set `DATABASE_URL` to the connection string for the intended database and set a unique `JWT_ACCESS_SECRET` of at least 32 bytes. Keep the env file and database credentials out of source control and out of the Flutter app.
4. In PowerShell, initialize the schema and seed missing demo accounts:

   ```powershell
   Set-Location backend
   .\.venv\Scripts\Activate.ps1
   python -m scripts.init_db
   python -m scripts.seed_demo
   ```

   If `backend/.venv` does not exist, create it with `python -m venv .venv`, then install `python -m pip install -r requirements.txt`.

Both commands are repeatable. Schema initialization creates missing tables/indexes, applies additive schema changes, and reconciles pre-ledger inventory as opening stock. The seed script adds missing demo admin/owner/shop records; it does not reset existing account passwords. Configure demo identifiers and passwords in `backend/.env` before seeding a new database.

## Run the application

Start the API in one PowerShell window:

```powershell
Set-Location backend
uvicorn app.main:app --reload --host 127.0.0.1 --port 8000
```

Verify `http://127.0.0.1:8000/health` and `http://127.0.0.1:8000/ready`. Readiness must return HTTP 200 with the connected database before using data-backed screens. If the API port is already occupied, identify and stop only the stale pharmacy API process; do not silently change ports or stop an unrelated process.

Start Flutter in another PowerShell window:

```powershell
Set-Location frontend
flutter pub get
flutter run -d web-server --web-hostname 127.0.0.1 --web-port 5200 --dart-define=API_BASE_URL=http://127.0.0.1:8000
```

Open `http://127.0.0.1:5200`. The local origin is included in `backend/.env.example` CORS settings. For Android emulators, use `http://10.0.2.2:8000` as `API_BASE_URL`; for other devices, use a reachable backend host and allow the frontend origin in `CORS_ORIGINS`.

FastAPI endpoints use the `/api` prefix; interactive API docs are at `http://127.0.0.1:8000/docs`.

The welcome screen, sign-in page, and authenticated Settings screen link to the in-app Terms of Use and Privacy Policy. These explain the application’s intended workflows and data handling; the organization operating a deployment must review and adapt them to its actual configuration and applicable requirements.

## Verify changes

```powershell
Set-Location backend
python -m pytest -q
python -m compileall -q app scripts tests
```

```powershell
Set-Location frontend
flutter analyze
flutter test
flutter build web --dart-define=API_BASE_URL=http://127.0.0.1:8000
```

## Data and operational notes

- Inventory quantities are recorded in `stock_movements`; stock adjustments are transactional. Review supplier invoice/OCR suggestions before adding stock.
- Bill-image OCR requires both the Python packages and the Tesseract executable. OCR only suggests bill lines; it does not alter inventory.
- Email delivery requires SMTP configuration. Without SMTP, recorded notifications remain available in the app.
- The API remains available for liveness when PostgreSQL is unavailable, but `/ready` and database-backed operations return an explicit error; they never use a fallback database.
- Never commit env files, tokens, database dumps, patient/customer data, or real invoices.
