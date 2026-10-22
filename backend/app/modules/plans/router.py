"""Plans router: catalog + self-serve plan selection."""

from datetime import datetime, timedelta, timezone
from typing import Any

from fastapi import APIRouter, Depends
from pydantic import BaseModel, Field

from app.common.deps import get_current_user, get_db
from app.core.errors import ApiError
from app.db.serialize import serialize
from app.modules.audit import service as audit
from app.modules.plans import catalog
from app.modules.users import service as users

router = APIRouter(prefix="/plans", tags=["Plans"])


class SelectPlanIn(BaseModel):
    plan: str = Field(min_length=1, max_length=32)


@router.get("")
async def list_plans(
    user: dict[str, Any] = Depends(get_current_user),
) -> Any:
    """Public catalog for any signed-in user, with the current plan marked."""
    return serialize(
        {
            "plans": [catalog.describe(plan) for plan in catalog.PLAN_CATALOG],
            "currentPlan": user.get("plan") or catalog.PLAN_IDS[0],
        }
    )


@router.post("/select")
async def select_plan(
    payload: SelectPlanIn,
    user: dict[str, Any] = Depends(get_current_user),
    db: Any = Depends(get_db),
) -> Any:
    plan = catalog.get_plan(payload.plan)
    if plan is None:
        raise ApiError(
            400,
            "PLAN_NOT_FOUND",
            "Unknown plan. Choose one of: " + ", ".join(catalog.PLAN_IDS),
        )
    now = datetime.now(timezone.utc)
    await users.update_profile_fields(
        db,
        str(user["sub"]),
        {
            "plan": plan.id,
            "planStartedAt": now,
            "planExpiresAt": now + timedelta(days=plan.duration_days),
            "planPaymentStatus": "DEV_MODE_UNPAID",
        },
    )
    await audit.record(
        db,
        actor_user_id=str(user["sub"]),
        actor_role=str(user.get("role") or "UNKNOWN"),
        store_id=user.get("storeId"),
        action="plans.select",
        target_type="user",
        target_id=str(user["sub"]),
        result="SUCCESS",
    )
    return serialize(
        {
            "plan": catalog.describe(plan),
            "planStartedAt": now,
            "planExpiresAt": now + timedelta(days=plan.duration_days),
            "note": "Development mode: no gateway is charged. Attach a payment provider to collect money.",
        }
    )
