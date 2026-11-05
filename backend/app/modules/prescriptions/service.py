import uuid
from datetime import datetime, timezone
from typing import Any

from app.core.errors import ApiError
from app.db.postgres import get_pg_connection
from app.modules.audit import service as audit


async def find_by_shop(db: Any, shop_id: str) -> list[dict[str, Any]]:
    pool = await get_pg_connection(db)
    async with pool.acquire() as conn:
        rows = await conn.fetch(
            "SELECT * FROM prescriptions WHERE shop_id = $1 ORDER BY created_at DESC",
            shop_id
        )
        return [dict(row) for row in rows]


async def find_by_id(db: Any, shop_id: str, prescription_id: str) -> dict[str, Any]:
    pool = await get_pg_connection(db)
    row = await pool.fetchrow(
        "SELECT * FROM prescriptions WHERE id = $1 AND shop_id = $2",
        prescription_id,
        shop_id,
    )
    if not row:
        raise ApiError(404, "PRESCRIPTION_NOT_FOUND", "Prescription not found")
    return dict(row)


async def update(
    db: Any,
    shop_id: str,
    prescription_id: str,
    payload: dict[str, Any],
    actor_id: str | None = None,
    actor_role: str = "SHOP_OWNER",
) -> dict[str, Any]:
    """Update a prescription (status, quantity, notes or patient details)."""
    await find_by_id(db, shop_id, prescription_id)
    mapping = {
        "patientName": "patient_name",
        "patientPhone": "patient_phone",
        "medicineName": "medicine_name",
        "status": "status",
        "notes": "notes",
    }
    set_parts: list[str] = []
    args: list[Any] = []
    for key, column in mapping.items():
        if key in payload and payload[key] is not None:
            value = str(payload[key]).strip()
            if not value:
                continue
            args.append(value)
            set_parts.append(f"{column} = ${len(args)}")
    if "quantity" in payload and payload["quantity"] is not None:
        quantity = int(payload["quantity"])
        if quantity < 1:
            raise ApiError(400, "VALIDATION_ERROR", "quantity must be at least 1")
        args.append(quantity)
        set_parts.append(f"quantity = ${len(args)}")
    if not set_parts:
        return await find_by_id(db, shop_id, prescription_id)

    args.extend([datetime.now(timezone.utc), prescription_id, shop_id])
    pool = await get_pg_connection(db)
    row = await pool.fetchrow(
        f"""UPDATE prescriptions SET {', '.join(set_parts)}, updated_at = ${len(args) - 2}
            WHERE id = ${len(args) - 1} AND shop_id = ${len(args)} RETURNING *""",
        *args,
    )
    if not row:
        raise ApiError(404, "PRESCRIPTION_NOT_FOUND", "Prescription not found")
    if actor_id:
        await audit.record(
            db,
            actor_user_id=actor_id,
            actor_role=actor_role,
            store_id=shop_id,
            action="owner.prescription.update",
            target_type="prescription",
            target_id=prescription_id,
            result="SUCCESS",
        )
    return dict(row)


async def delete(
    db: Any,
    shop_id: str,
    prescription_id: str,
    actor_id: str | None = None,
    actor_role: str = "SHOP_OWNER",
) -> None:
    """Remove a prescription. Bills and stock are never touched."""
    await find_by_id(db, shop_id, prescription_id)
    pool = await get_pg_connection(db)
    await pool.execute(
        "DELETE FROM prescriptions WHERE id = $1 AND shop_id = $2",
        prescription_id,
        shop_id,
    )
    if actor_id:
        await audit.record(
            db,
            actor_user_id=actor_id,
            actor_role=actor_role,
            store_id=shop_id,
            action="owner.prescription.delete",
            target_type="prescription",
            target_id=prescription_id,
            result="SUCCESS",
        )


async def create(
    db: Any,
    data: dict[str, Any],
    actor_id: str | None = None,
    actor_role: str = "SHOP_OWNER",
) -> dict[str, Any]:
    for field in ("patientName", "medicineName"):
        if not str(data.get(field) or "").strip():
            raise ApiError(400, "VALIDATION_ERROR", f"{field} is required")
    try:
        quantity = int(data.get("quantity"))
    except (TypeError, ValueError):
        raise ApiError(400, "VALIDATION_ERROR", "quantity must be at least 1") from None
    if quantity < 1:
        raise ApiError(400, "VALIDATION_ERROR", "quantity must be at least 1")

    pool = await get_pg_connection(db)
    now = datetime.now(timezone.utc)
    prescription_id = str(uuid.uuid4())
    document = {
        "id": prescription_id,
        "shop_id": str(data["shopId"]),
        "patient_name": str(data["patientName"]).strip(),
        "medicine_name": str(data["medicineName"]).strip(),
        "quantity": quantity,
        "status": data.get("status") or "pending",
        "created_at": now,
        "updated_at": now,
        "__v": 0,
    }
    if actor_id:
        document["created_by"] = actor_id
    if data.get("patientPhone"):
        document["patient_phone"] = str(data["patientPhone"]).strip()
    if data.get("notes"):
        document["notes"] = str(data["notes"]).strip()
    await pool.execute(
        "INSERT INTO prescriptions (id, shop_id, patient_name, medicine_name, quantity, status, created_at, updated_at, created_by) VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9)",
        prescription_id, document["shop_id"], document["patient_name"], document["medicine_name"],
        document["quantity"], document["status"], document["created_at"], document["updated_at"], document.get("created_by")
    )
    if actor_id:
        await audit.record(
            db,
            actor_user_id=actor_id,
            actor_role=actor_role,
            store_id=document["shop_id"],
            action="owner.prescription.create",
            target_type="prescription",
            target_id=prescription_id,
            result="SUCCESS",
        )
    return document
