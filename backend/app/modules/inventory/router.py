from fastapi import APIRouter, HTTPException, Request

router = APIRouter(prefix="/stores/{store_id}/inventory", tags=["Inventory"])


@router.get("/connectivity")
async def inventory_connectivity(request: Request) -> dict[str, str]:
    """Scaffold-only endpoint confirming that the inventory route is registered.

    This does not query or modify stock. Replace/remove it when real inventory APIs
    are implemented and protected by store-level authentication/authorization.
    """
    if getattr(request.app.state, "db", None) is None:
        raise HTTPException(status_code=503, detail={"code": "DATABASE_NOT_CONFIGURED", "message": "Postgres is not configured"})
    return {"status": "route-ready", "note": "No inventory operation was performed"}
