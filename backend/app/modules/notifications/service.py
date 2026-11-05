import logging
from datetime import datetime, timezone
from typing import Any

from app.core.config import get_settings
from app.core.errors import ApiError
from app.db.postgres import get_pg_connection

logger = logging.getLogger("pharmacy.notifications")


async def send_owner_invite(destination: str, temp_password: str) -> None:
    if get_settings().is_development:
        logger.info(
            "[DEV-DELIVERY] OWNER ACTIVATION -> %s : temporary password = %s",
            destination,
            temp_password,
        )
        return
    logger.warning("Owner activation requested but no production delivery provider is configured")


async def send_recovery_credential(destination: str, temp_password: str) -> None:
    if get_settings().is_development:
        logger.info(
            "[DEV-DELIVERY] PASSWORD RECOVERY -> %s : temporary password = %s",
            destination,
            temp_password,
        )
        return
    logger.warning("Password recovery requested but no production delivery provider is configured")


async def send_otp(destination: str, channel: str, code: str) -> None:
    if get_settings().is_development:
        logger.info(
            "[DEV-DELIVERY] %s OTP -> %s : code = %s (expires soon)",
            channel,
            destination,
            code,
        )
        return
    logger.warning("Contact verification requested but no production delivery provider is configured")


async def notify(
    db: Any,
    *,
    user_id: str,
    title: str,
    message: str,
    type_: str = "SYSTEM",
    store_id: str | None = None,
) -> None:
    """Persist an in-app notification using PostgreSQL."""
    now = datetime.now(timezone.utc)
    pool = await get_pg_connection(db)
    await pool.execute(
        """INSERT INTO notifications
           (user_id, store_id, title, message, type, is_read, created_at, updated_at)
           VALUES ($1, $2, $3, $4, $5, FALSE, $6, $6)""",
        user_id,
        store_id or None,
        title,
        message,
        type_,
        now,
    )


async def broadcast_admins(
    db: Any,
    *,
    title: str,
    message: str,
    type_: str = "SYSTEM",
    store_id: str | None = None,
) -> None:
    """Alert every active SUPER_ADMIN. Never breaks the caller flow."""
    try:
        pool = await get_pg_connection(db)
        rows = await pool.fetch(
            "SELECT id FROM users WHERE role = $1 AND status = $2",
            "SUPER_ADMIN",
            "ACTIVE",
        )
        for row in rows:
            await notify(
                db,
                user_id=str(row["id"]),
                title=title,
                message=message,
                type_=type_,
                store_id=store_id,
            )
    except Exception:  # notifications are best-effort
        logger.exception("admin broadcast failed")


async def list_notifications(db: Any, user_id: str) -> list[dict[str, Any]]:
    pool = await get_pg_connection(db)
    rows = await pool.fetch(
        "SELECT * FROM notifications WHERE user_id = $1 ORDER BY created_at DESC LIMIT 50",
        user_id,
    )
    return [dict(row) for row in rows]


async def unread_count(db: Any, user_id: str) -> int:
    pool = await get_pg_connection(db)
    row = await pool.fetchrow(
        "SELECT COUNT(*) AS total FROM notifications WHERE user_id = $1 AND is_read = FALSE",
        user_id,
    )
    return int(row["total"]) if row else 0


async def mark_read(db: Any, user_id: str, notification_id: str) -> None:
    pool = await get_pg_connection(db)
    now = datetime.now(timezone.utc)
    result = await pool.execute(
        """UPDATE notifications SET is_read = TRUE, read_at = $1, updated_at = $1
           WHERE id = $2 AND user_id = $3""",
        now,
        notification_id,
        user_id,
    )
    if result.endswith(" 0"):
        raise ApiError(404, "NOTIFICATION_NOT_FOUND", "Notification not found")


async def mark_all_read(db: Any, user_id: str) -> dict[str, int]:
    pool = await get_pg_connection(db)
    now = datetime.now(timezone.utc)
    result = await pool.execute(
        """UPDATE notifications SET is_read = TRUE, read_at = $1, updated_at = $1
           WHERE user_id = $2 AND is_read = FALSE""",
        now,
        user_id,
    )
    try:
        updated = int(result.split()[-1])
    except (ValueError, IndexError):
        updated = 0
    return {"updated": updated}


async def delete_notification(db: Any, user_id: str, notification_id: str) -> None:
    pool = await get_pg_connection(db)
    result = await pool.execute(
        "DELETE FROM notifications WHERE id = $1 AND user_id = $2",
        notification_id,
        user_id,
    )
    if result.endswith(" 0"):
        raise ApiError(404, "NOTIFICATION_NOT_FOUND", "Notification not found")


async def action_required(db: Any, user: dict[str, Any]) -> list[dict[str, Any]]:
    """Steps the signed-in user still has to complete before work can continue.

    The list drives both the in-app popup and the action-required emails, so
    both surfaces always agree on what is pending.
    """
    pool = await get_pg_connection(db)
    user_id = str(user.get("sub") or "")
    role = str(user.get("role") or "SHOP_OWNER")
    actions: list[dict[str, Any]] = []

    if role == "SUPER_ADMIN":
        open_row = await pool.fetchrow(
            "SELECT COUNT(*) AS total FROM issues WHERE status <> 'RESOLVED'"
        )
        open_count = int(open_row["total"]) if open_row else 0
        if open_count:
            actions.append(
                {
                    "key": "open_issues",
                    "title": f"{open_count} issue(s) waiting for you",
                    "message": "Owners reported problems that are still open.",
                    "severity": "HIGH",
                    "route": "/admin-issues",
                    "count": open_count,
                }
            )
        invited_row = await pool.fetchrow(
            """SELECT COUNT(*) AS total FROM users
               WHERE role = 'SHOP_OWNER' AND status = 'INVITED'"""
        )
        invited_count = int(invited_row["total"]) if invited_row else 0
        if invited_count:
            actions.append(
                {
                    "key": "pending_first_login",
                    "title": f"{invited_count} owner(s) have not signed in yet",
                    "message": "Credentials were sent, but the account is still unused.",
                    "severity": "MEDIUM",
                    "route": "/shops",
                    "count": invited_count,
                }
            )
        return actions

    owner = await pool.fetchrow("SELECT * FROM users WHERE id = $1", user_id)
    if owner is None:
        return actions

    if owner["must_change_password"]:
        actions.append(
            {
                "key": "change_password",
                "title": "Set a new password",
                "message": "Your temporary password expires soon. Choose a new one to continue.",
                "severity": "HIGH",
                "route": "/account-setup",
                "count": 1,
            }
        )
    if not (owner["phone_verified_at"] or owner["email_verified_at"]):
        actions.append(
            {
                "key": "verify_contact",
                "title": "Verify your contact",
                "message": "Confirm your email or mobile so we can send receipts and alerts.",
                "severity": "MEDIUM",
                "route": "/account-setup",
                "count": 1,
            }
        )
    if not owner["profile_completed_at"]:
        actions.append(
            {
                "key": "complete_profile",
                "title": "Complete your shop profile",
                "message": "Add the shop address and contact so bills and invoices look right.",
                "severity": "MEDIUM",
                "route": "/account-setup",
                "count": 1,
            }
        )
    store_id = owner["owner_store_id"]
    if store_id:
        shop = await pool.fetchrow(
            "SELECT shop_name, status FROM shops WHERE id = $1", store_id
        )
        if shop and shop["status"] == "SUSPENDED":
            actions.append(
                {
                    "key": "shop_suspended",
                    "title": f"{shop['shop_name']} is suspended",
                    "message": "Billing is blocked until the admin reactivates this shop.",
                    "severity": "HIGH",
                    "route": "/settings",
                    "count": 1,
                }
            )
    return actions
