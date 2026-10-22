import re
import uuid
from datetime import datetime, timezone
from typing import Any

from asyncpg import UniqueViolationError

from app.core.errors import ApiError
from app.db.postgres import get_pg_connection
from app.modules.audit import service as audit
from app.modules.notifications import service as notifications
from app.modules.users.service import object_id


async def create_customer(
    db: Any,
    store_id: str,
    actor_id: str,
    *,
    name: str,
    phone: str | None = None,
    notes: str | None = None,
) -> dict[str, Any]:
    pool = await get_pg_connection(db)
    async with pool.acquire() as conn:
        if phone:
            existing = await conn.fetchrow(
                "SELECT * FROM customers WHERE store_id = $1 AND phone = $2",
                store_id, phone
            )
            if existing:
                raise ApiError(409, "CUSTOMER_EXISTS", "A customer with this phone already exists")
        now = datetime.now(timezone.utc)
        customer_id = str(uuid.uuid4())
        await conn.execute(
            "INSERT INTO customers (id, store_id, name, phone, balance, created_by, created_at, updated_at) VALUES ($1, $2, $3, $4, $5, $6, $7, $8)",
            customer_id, store_id, name.strip(), phone, 0.0, actor_id, now, now
        )
        result_id = customer_id
    await audit.record(
        db,
        actor_user_id=actor_id,
        actor_role="SHOP_OWNER",
        store_id=store_id,
        action="owner.customer.create",
        target_type="customer",
        target_id=result_id,
        result="SUCCESS",
    )
    return {"id": result_id, "store_id": store_id, "name": name.strip(), "phone": phone, "balance": 0.0}


async def list_customers(
    db: Any,
    store_id: str,
    search: str | None = None,
    limit: int = 100,
) -> list[dict[str, Any]]:
    pool = await get_pg_connection(db)
    async with pool.acquire() as conn:
        query = "SELECT * FROM customers WHERE store_id = $1"
        args = [store_id]
        if search and search.strip():
            pattern = f"%{search.strip()}%"
            query += " AND (name ILIKE $" + str(len(args) + 1) + " OR phone ILIKE $" + str(len(args) + 2) + ")"
            args.extend([pattern, pattern])
        query += " ORDER BY updated_at DESC"
        query += " LIMIT $" + str(len(args) + 1)
        args.append(limit)
        rows = await conn.fetch(query, *args)
        return [dict(row) for row in rows]


async def find_customer(db: Any, store_id: str, customer_id: str) -> dict[str, Any]:
    pool = await get_pg_connection(db)
    async with pool.acquire() as conn:
        row = await conn.fetchrow(
            "SELECT * FROM customers WHERE id = $1 AND store_id = $2",
            customer_id, store_id
        )
        if row:
            return dict(row)
    raise ApiError(404, "CUSTOMER_NOT_FOUND", "Customer not found")


async def customer_detail(db: Any, store_id: str, customer_id: str) -> dict[str, Any]:
    customer = await find_customer(db, store_id, customer_id)
    pool = await get_pg_connection(db)
    async with pool.acquire() as conn:
        bills_rows = await conn.fetch(
            "SELECT * FROM bills WHERE store_id = $1 AND customer_id = $2 ORDER BY created_at DESC LIMIT 50",
            store_id, customer_id
        )
        payments_rows = await conn.fetch(
            "SELECT * FROM customer_payments WHERE store_id = $1 AND customer_id = $2 ORDER BY created_at DESC LIMIT 50",
            store_id, customer_id
        )
    return {
        "customer": customer,
        "bills": [dict(row) for row in bills_rows],
        "payments": [dict(row) for row in payments_rows],
    }


async def update_customer(
    db: Any,
    store_id: str,
    customer_id: str,
    patch: dict[str, Any],
) -> dict[str, Any]:
    customer = await find_customer(db, store_id, customer_id)
    clean = {key: value for key, value in patch.items() if value is not None}
    if not clean:
        return customer
    if "name" in clean:
        clean["name"] = clean["name"].strip()
    pool = await get_pg_connection(db)
    async with pool.acquire() as conn:
        await conn.execute(
            "UPDATE customers SET name = $1, updated_at = $2 WHERE id = $3",
            clean.get("name", customer.get("name")), datetime.now(timezone.utc), customer_id
        )
        row = await conn.fetchrow(
            "SELECT * FROM customers WHERE id = $1", customer_id
        )
    return dict(row) or customer


async def delete_customer(
    db: Any,
    store_id: str,
    customer_id: str,
    actor_id: str,
) -> None:
    """Delete a customer that has no bills yet.

    Customers with bills stay in the ledger: their balance and bill history
    must remain readable.
    """
    await find_customer(db, store_id, customer_id)
    pool = await get_pg_connection(db)
    bill_row = await pool.fetchrow(
        "SELECT COUNT(*) AS total FROM bills WHERE customer_id = $1", customer_id
    )
    if bill_row and int(bill_row["total"]) > 0:
        raise ApiError(
            409,
            "CUSTOMER_HAS_BILLS",
            "This customer has bills and cannot be deleted",
        )
    await pool.execute(
        "DELETE FROM customers WHERE id = $1 AND store_id = $2", customer_id, store_id
    )
    await audit.record(
        db,
        actor_user_id=actor_id,
        actor_role="SHOP_OWNER",
        store_id=store_id,
        action="owner.customer.delete",
        target_type="customer",
        target_id=customer_id,
        result="SUCCESS",
    )


async def record_payment(
    db: Any,
    store_id: str,
    customer_id: str,
    actor_id: str,
    amount: float,
    note: str | None = None,
) -> dict[str, Any]:
    pool = await get_pg_connection(db)
    customer = await find_customer(db, store_id, customer_id)
    now = datetime.now(timezone.utc)
    new_balance = max(0.0, float(customer.get("balance") or 0) - amount)
    await pool.execute(
        "UPDATE customers SET balance = $1, updated_at = $2 WHERE id = $3",
        new_balance, datetime.now(timezone.utc), customer_id
    )
    payment_id = str(uuid.uuid4())
    await pool.execute(
        "INSERT INTO customer_payments (id, store_id, customer_id, amount, note, created_by, created_at) VALUES ($1, $2, $3, $4, $5, $6, $7)",
        payment_id, store_id, customer_id, amount, note, actor_id, now
    )
    await notifications.notify(
        db,
        user_id=actor_id,
        store_id=store_id,
        title="Payment recorded",
        message=f"₹{amount:.2f} received from {customer['name']}. Balance now ₹{new_balance:.2f}.",
        type_="PAYMENT",
    )
    await audit.record(
        db,
        actor_user_id=actor_id,
        actor_role="SHOP_OWNER",
        store_id=store_id,
        action="owner.customer.payment",
        target_type="customer",
        target_id=customer_id,
        result="SUCCESS",
    )
    # Return updated customer
    customer = await find_customer(db, store_id, customer_id)
    customer["balance"] = new_balance
    return customer
