from fastapi import APIRouter

from app.modules.inventory.router import router as inventory_router
from app.modules.expiry_low_stock_reconciliation.router import (
    router as expiry_low_stock_reconciliation_router,
)

api_router = APIRouter()

api_router.include_router(inventory_router, tags=["Inventory scaffold"])
api_router.include_router(
    expiry_low_stock_reconciliation_router,
    tags=["Expiry, Low Stock & Reconciliation"],
)
