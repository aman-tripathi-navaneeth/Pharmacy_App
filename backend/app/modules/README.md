# Module packages

Each module has its own router and service. The active API router in `app/api/router.py` registers the module routes under the `/api` prefix. Require authentication and enforce store-level authorization before exposing shop data. PostgreSQL is the only database; use `backend/schema.sql` and `python scripts/init_db.py` to provision it.
