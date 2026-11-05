"""Issue reports: shop owners report problems, the super admin monitors them.

The super admin has nobody above them, so issues flow only upward:
SHOP_OWNER creates -> SUPER_ADMIN tracks and resolves.
"""

import logging
import uuid
from datetime import datetime, timezone
from typing import Any

from app.core.errors import ApiError
from app.db.postgres import get_pg_connection
from app.modules.email import service as email_service
from app.modules.notifications import service as notifications

STATUSES = ("OPEN", "IN_PROGRESS", "RESOLVED")
CATEGORIES = ("BILLING", "STOCK", "APP_BUG", "OTHER")
logger = logging.getLogger("pharmacy.issues")


async def create_issue(
    db: Any,
    actor: dict[str, Any],
    title: str,
    description: str,
    category: str | None = None,
) -> dict[str, Any]:
    pool = await get_pg_connection(db)
    now = datetime.now(timezone.utc)
    issue_id = str(uuid.uuid4())
    store_id = actor.get("storeId") or None
    await pool.execute(
        """INSERT INTO issues
           (id, store_id, created_by, created_by_role, created_by_name, category,
            title, description, status, created_at, updated_at)
           VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $10)""",
        issue_id,
        store_id,
        str(actor.get("sub") or actor.get("_id")),
        str(actor.get("role") or "SHOP_OWNER"),
        str(actor.get("fullName") or ""),
        category if category in CATEGORIES else "OTHER",
        title.strip(),
        description.strip(),
        "OPEN",
        now,
    )
    # Every new owner issue lands on the super admin as an alert.
    await notifications.broadcast_admins(
        db,
        title="New issue reported",
        message=f"A shop owner reported: {title}",
        type_="ISSUE",
    )
    await _email_admins_about_issue(
        db,
        issue_title=title,
        issue_category=category if category in CATEGORIES else "OTHER",
        issue_description=description,
        store_id=str(store_id) if store_id else None,
        owner_name=str(actor.get("fullName") or "A shop owner"),
    )
    return {
        "id": issue_id,
        "store_id": store_id,
        "created_by": str(actor.get("sub") or ""),
        "category": category if category in CATEGORIES else "OTHER",
        "title": title.strip(),
        "description": description.strip(),
        "status": "OPEN",
        "created_at": now,
    }


async def list_issues(
    db: Any,
    actor: dict[str, Any],
    status: str | None = None,
    store_id: str | None = None,
) -> list[dict[str, Any]]:
    pool = await get_pg_connection(db)
    query = "SELECT * FROM issues WHERE 1=1"
    args: list[Any] = []
    if actor.get("role") != "SUPER_ADMIN":
        args.append(str(actor.get("sub") or ""))
        query += " AND created_by = $" + str(len(args))
    if store_id:
        args.append(store_id)
        query += " AND store_id = $" + str(len(args))
    if status in STATUSES:
        args.append(status)
        query += " AND status = $" + str(len(args))
    args.append(100)
    query += " ORDER BY created_at DESC LIMIT $" + str(len(args))
    rows = await pool.fetch(query, *args)
    return [dict(row) for row in rows]


async def find_issue(db: Any, issue_id: str) -> dict[str, Any]:
    pool = await get_pg_connection(db)
    row = await pool.fetchrow("SELECT * FROM issues WHERE id = $1", issue_id)
    if row:
        return dict(row)
    raise ApiError(404, "ISSUE_NOT_FOUND", "Issue not found")


async def update_status(
    db: Any,
    issue_id: str,
    status: str,
    note: str | None,
    admin_id: str,
) -> dict[str, Any]:
    if status not in STATUSES:
        raise ApiError(400, "INVALID_STATUS", "Status must be OPEN, IN_PROGRESS or RESOLVED")
    issue = await find_issue(db, issue_id)
    now = datetime.now(timezone.utc)
    cleaned_note = note.strip()[:500] if note and note.strip() else None
    pool = await get_pg_connection(db)
    row = await pool.fetchrow(
        """UPDATE issues
           SET status = $1, admin_notes = COALESCE($2, admin_notes),
               resolution_note = COALESCE($2, resolution_note), updated_at = $3
           WHERE id = $4 RETURNING *""",
        status,
        cleaned_note,
        now,
        issue_id,
    )

    await notifications.notify(
        db,
        user_id=str(issue["created_by"]),
        store_id=str(issue["store_id"]) if issue.get("store_id") else None,
        title=f"Issue {status.replace('_', ' ').lower()}",
        message=f"Your report '{issue['title']}' is now '{status}'.",
        type_="ISSUE",
    )
    await _email_owner_about_status(
        db,
        issue=issue,
        status=status,
        note=cleaned_note,
    )
    return dict(row) if row else issue


async def _email_admins_about_issue(
    db: Any,
    *,
    issue_title: str,
    issue_category: str,
    issue_description: str,
    store_id: str | None,
    owner_name: str,
) -> None:
    """Email every active super admin when an owner raises an issue."""
    try:
        pool = await get_pg_connection(db)
        shop_name = ""
        if store_id:
            shop_row = await pool.fetchrow(
                "SELECT shop_name FROM shops WHERE id = $1", store_id
            )
            shop_name = str(shop_row["shop_name"]) if shop_row else ""
        admins = await pool.fetch(
            """SELECT email_normalized FROM users
               WHERE role = 'SUPER_ADMIN' AND status = 'ACTIVE'
                 AND email_normalized IS NOT NULL"""
        )
        for admin_row in admins:
            await email_service.send_issue_raised_email(
                db,
                to_email=admin_row["email_normalized"],
                issue_title=issue_title,
                issue_category=issue_category,
                issue_description=issue_description,
                shop_name=shop_name or None,
                owner_name=owner_name,
                store_id=store_id,
            )
    except Exception:
        logger.exception("Could not email admins about issue %s", issue_title)


async def _email_owner_about_status(
    db: Any,
    *,
    issue: dict[str, Any],
    status: str,
    note: str | None,
) -> None:
    """Email the owner when the admin moves their issue to a new status."""
    try:
        pool = await get_pg_connection(db)
        owner_id = str(issue.get("created_by") or "")
        if not owner_id:
            return
        owner = await pool.fetchrow(
            "SELECT full_name, email_normalized FROM users WHERE id = $1", owner_id
        )
        if not owner or not owner["email_normalized"]:
            return
        shop_name = ""
        if issue.get("store_id"):
            shop_row = await pool.fetchrow(
                "SELECT shop_name FROM shops WHERE id = $1", issue["store_id"]
            )
            shop_name = str(shop_row["shop_name"]) if shop_row else ""
        await email_service.send_issue_status_email(
            db,
            to_email=owner["email_normalized"],
            recipient_name=str(owner["full_name"] or "there"),
            issue_title=str(issue.get("title") or "Your issue"),
            issue_status=status,
            issue_note=note,
            shop_name=shop_name or None,
            store_id=str(issue["store_id"]) if issue.get("store_id") else None,
            user_id=owner_id,
        )
    except Exception:
        logger.exception(
            "Could not email the owner about issue status for %s",
            issue.get("id"),
        )
