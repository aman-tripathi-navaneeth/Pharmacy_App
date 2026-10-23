from fastapi import APIRouter

from app.modules.inventory.router import router as inventory_router
from app.modules.today_dashboard_reports.router import router as dashboard_reports_router

api_router = APIRouter()
api_router.include_router(inventory_router, tags=["Inventory scaffold"])
api_router.include_router(dashboard_reports_router)