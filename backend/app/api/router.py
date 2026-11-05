from fastapi import APIRouter

from app.modules.admin.router import router as admin_router
from app.modules.audit.router import router as audit_router
from app.modules.auth.router import router as auth_router
from app.modules.bills.router import router as bills_router
from app.modules.customers.router import router as customers_router
from app.modules.email.router import router as email_router
from app.modules.expiry_low_stock_reconciliation.router import (
    router as expiry_low_stock_reconciliation_router,
)
from app.modules.inventory.router import router as inventory_router
from app.modules.inventory_batches_stock_ledger.router import (
    router as inventory_batches_stock_ledger_router,
)
from app.modules.issues.router import router as issues_router
from app.modules.notifications.router import router as notifications_router
from app.modules.onboarding.router import router as onboarding_router
from app.modules.plans.router import router as plans_router
from app.modules.prescriptions.router import router as prescriptions_router
from app.modules.reports.router import router as reports_router
from app.modules.shops.router import router as shops_router
from app.modules.suppliers.router import router as suppliers_router
from app.modules.sync.router import router as sync_router
from app.modules.users.router import router as users_router

api_router = APIRouter()
api_router.include_router(auth_router)
api_router.include_router(users_router)
api_router.include_router(shops_router)
api_router.include_router(suppliers_router)
api_router.include_router(sync_router)
api_router.include_router(admin_router)
api_router.include_router(onboarding_router)
api_router.include_router(notifications_router)
api_router.include_router(audit_router)
api_router.include_router(inventory_router)
api_router.include_router(inventory_batches_stock_ledger_router, tags=["Inventory, Batches & Stock Ledger"])
api_router.include_router(
    expiry_low_stock_reconciliation_router,
    tags=["Expiry, Low Stock & Reconciliation"],
)
api_router.include_router(plans_router)
api_router.include_router(issues_router)
api_router.include_router(customers_router)
api_router.include_router(bills_router)
api_router.include_router(reports_router)
api_router.include_router(prescriptions_router)
api_router.include_router(email_router)
