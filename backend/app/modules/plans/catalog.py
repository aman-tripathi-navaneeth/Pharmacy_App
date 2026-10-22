"""Static subscription plan catalog.

Plans are a dev/self-serve tier catalogue: owners pick a plan and the shop
owner's user record stores it. A payment gateway can be attached later; the
plan value is validated, never free-form.
"""

from dataclasses import dataclass, field


@dataclass(frozen=True)
class Plan:
    id: str
    name: str
    price_inr: int
    duration_days: int
    features: list[str] = field(default_factory=list)
    max_inventory_items: int | None = None


PLAN_CATALOG: list[Plan] = [
    Plan(
        id="TRIAL",
        name="Free trial",
        price_inr=0,
        duration_days=30,
        features=[
            "Full Phase 1 app access for 30 days",
            "Billing, stock and udhaar book",
            "Email support in English",
        ],
    ),
    Plan(
        id="BASIC",
        name="Basic",
        price_inr=199,
        duration_days=30,
        features=[
            "Billing, inventory and customers",
            "Sales report (basic totals)",
            "Up to 200 stock items",
        ],
        max_inventory_items=200,
    ),
    Plan(
        id="GROWTH",
        name="Growth",
        price_inr=399,
        duration_days=30,
        features=[
            "Everything in Basic",
            "Unlimited stock items",
            "Reports with PDF/Excel export",
        ],
        max_inventory_items=None,
    ),
]

PLAN_IDS = [plan.id for plan in PLAN_CATALOG]


def get_plan(plan_id: str | None) -> Plan | None:
    if not plan_id:
        return None
    for plan in PLAN_CATALOG:
        if plan.id == plan_id:
            return plan
    return None


def describe(plan: Plan) -> dict:
    return {
        "id": plan.id,
        "name": plan.name,
        "priceInr": plan.price_inr,
        "durationDays": plan.duration_days,
        "features": plan.features,
        "maxInventoryItems": plan.max_inventory_items,
    }
