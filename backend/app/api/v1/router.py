from fastapi import APIRouter

from app.modules.inventory_batches_stock_ledger.router import router as inventory_router

api_router = APIRouter()
api_router.include_router(inventory_router, tags=["Inventory, Batches & Stock Ledger"])
