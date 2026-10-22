"""SMTP delivery with a durable log.

Every send attempt - successful, failed or skipped because SMTP is not
configured - is written to the ``email_logs`` table so the app can show a
complete email history. Delivery problems never bubble up into the business
flow that triggered the email.
"""

import asyncio
import logging
import smtplib
import uuid
from datetime import datetime, timezone
from email.message import EmailMessage
from email.utils import formataddr
from typing import Any

from app.core.config import get_settings
from app.db.postgres import get_pg_connection
from app.modules.email import templates

logger = logging.getLogger("pharmacy.email")

STATUS_SENT = "SENT"
STATUS_FAILED = "FAILED"
STATUS_SKIPPED = "SKIPPED"

PREVIEW_LENGTH = 240


def _as_uuid(value: Any) -> uuid.UUID | None:
    """Convert a stored id into a UUID, or None when it is not one."""
    if isinstance(value, uuid.UUID):
        return value
    if not value:
        return None
    try:
        return uuid.UUID(str(value))
    except (ValueError, TypeError, AttributeError):
        return None


async def _log_row(db: Any, **values: Any) -> dict[str, Any]:
    pool = await get_pg_connection(db)
    columns = [
        "template",
        "recipient_email",
        "recipient_name",
        "recipient_user_id",
        "store_id",
        "subject",
        "body_preview",
        "body_text",
        "status",
        "error_message",
        "provider",
        "is_action_required",
        "sent_at",
    ]
    payload = {
        "template": values.get("template") or "unknown",
        "recipient_email": (values.get("recipient_email") or "").lower(),
        "recipient_name": values.get("recipient_name"),
        "recipient_user_id": _as_uuid(values.get("recipient_user_id")),
        "store_id": _as_uuid(values.get("store_id")),
        "subject": values.get("subject") or "",
        "body_preview": values.get("body_preview"),
        "body_text": values.get("body_text"),
        "status": values.get("status") or STATUS_SKIPPED,
        "error_message": values.get("error_message"),
        "provider": values.get("provider") or "smtp",
        "is_action_required": bool(values.get("is_action_required")),
        "sent_at": values.get("sent_at"),
    }
    placeholders = ", ".join(["$" + str(index + 1) for index in range(len(columns))])
    args = [payload[column] for column in columns]
    row = await pool.fetchrow(
        f"INSERT INTO email_logs ({', '.join(columns)}) VALUES ({placeholders}) RETURNING *",
        *args,
    )
    return dict(row) if row else payload


async def _update_status(
    db: Any,
    log_id: str,
    *,
    status: str,
    error_message: str | None = None,
    sent_at: datetime | None = None,
) -> None:
    pool = await get_pg_connection(db)
    await pool.execute(
        """UPDATE email_logs
           SET status = $1, error_message = $2, sent_at = COALESCE($3, sent_at), updated_at = $4
           WHERE id = $5""",
        status,
        error_message,
        sent_at,
        datetime.now(timezone.utc),
        _as_uuid(log_id),
    )


def _deliver_via_smtp(settings: Any, message: EmailMessage) -> None:
    """Blocking SMTP send, executed in a worker thread."""
    timeout = settings.smtp_timeout_seconds
    if settings.smtp_use_ssl:
        server = smtplib.SMTP_SSL(settings.smtp_host, settings.smtp_port, timeout=timeout)
    else:
        server = smtplib.SMTP(settings.smtp_host, settings.smtp_port, timeout=timeout)
    with server:
        server.ehlo()
        if settings.smtp_use_tls and not settings.smtp_use_ssl:
            server.starttls()
            server.ehlo()
        if settings.smtp_username:
            server.login(settings.smtp_username, settings.smtp_password)
        server.send_message(message)


async def send_email(
    db: Any,
    *,
    to_email: str | None,
    template: str,
    context: dict[str, Any] | None = None,
    recipient_name: str | None = None,
    recipient_user_id: str | None = None,
    store_id: str | None = None,
    action_required: bool = False,
    notify: bool = False,
    notify_title: str | None = None,
    notify_message: str | None = None,
    notify_type: str = "EMAIL",
) -> dict[str, Any]:
    """Render, deliver and log one email. Never raises for delivery problems."""
    settings = get_settings()
    context = dict(context or {})
    context.setdefault("app_url", settings.app_base_url)
    context.setdefault("support_email", settings.support_email)
    if recipient_name:
        context.setdefault("recipient_name", recipient_name)

    rendered = templates.render(template, context)
    recipient = (to_email or "").strip()
    preview = rendered.text[:PREVIEW_LENGTH]

    if not recipient:
        record = await _log_row(
            db,
            template=template,
            recipient_email="",
            recipient_name=recipient_name,
            recipient_user_id=recipient_user_id,
            store_id=store_id,
            subject=rendered.subject,
            body_preview=preview,
            body_text=rendered.text,
            status=STATUS_SKIPPED,
            error_message="No email address on file",
            is_action_required=action_required,
        )
        logger.info("[EMAIL-SKIPPED] %s -> no address (%s)", template, rendered.subject)
        return record

    if not settings.mail_enabled:
        record = await _log_row(
            db,
            template=template,
            recipient_email=recipient,
            recipient_name=recipient_name,
            recipient_user_id=recipient_user_id,
            store_id=store_id,
            subject=rendered.subject,
            body_preview=preview,
            body_text=rendered.text,
            status=STATUS_SKIPPED,
            error_message="SMTP is not configured (set SMTP_HOST and SMTP_FROM_EMAIL)",
            is_action_required=action_required,
        )
        logger.info(
            "[EMAIL-DEV-DELIVERY] %s -> %s : %s",
            template,
            recipient,
            rendered.subject,
        )
        if notify and recipient_user_id:
            await _notify(
                db,
                user_id=recipient_user_id,
                store_id=store_id,
                title=notify_title or rendered.subject,
                message=notify_message or rendered.text[:200],
                type_=notify_type,
            )
        return record

    message = EmailMessage()
    message["Subject"] = rendered.subject
    message["From"] = formataddr((settings.smtp_from_name, settings.smtp_from_email))
    message["To"] = recipient
    if settings.support_email:
        message["Reply-To"] = settings.support_email
    message.set_content(rendered.text)
    message.add_alternative(rendered.html, subtype="html")

    record = await _log_row(
        db,
        template=template,
        recipient_email=recipient,
        recipient_name=recipient_name,
        recipient_user_id=recipient_user_id,
        store_id=store_id,
        subject=rendered.subject,
        body_preview=preview,
        body_text=rendered.text,
        status=STATUS_SKIPPED,
        error_message=None,
        is_action_required=action_required,
    )

    try:
        await asyncio.to_thread(_deliver_via_smtp, settings, message)
    except Exception as error:  # noqa: BLE001 - delivery failures are recorded, not raised
        detail = f"{type(error).__name__}: {error}"
        await _update_status(db, str(record["id"]), status=STATUS_FAILED, error_message=detail)
        logger.exception("Email delivery failed for %s", recipient)
        if notify and recipient_user_id:
            await _notify(
                db,
                user_id=recipient_user_id,
                store_id=store_id,
                title=notify_title or rendered.subject,
                message=notify_message or rendered.text[:200],
                type_=notify_type,
            )
        return {**record, "status": STATUS_FAILED, "error_message": detail}

    await _update_status(
        db,
        str(record["id"]),
        status=STATUS_SENT,
        error_message=None,
        sent_at=datetime.now(timezone.utc),
    )
    if notify and recipient_user_id:
        await _notify(
            db,
            user_id=recipient_user_id,
            store_id=store_id,
            title=notify_title or rendered.subject,
            message=notify_message or rendered.text[:200],
            type_=notify_type,
        )
    return {**record, "status": STATUS_SENT, "error_message": None}


async def _notify(
    db: Any,
    *,
    user_id: str,
    store_id: str | None,
    title: str,
    message: str,
    type_: str,
) -> None:
    try:
        from app.modules.notifications import service as notifications

        await notifications.notify(
            db,
            user_id=user_id,
            store_id=store_id,
            title=title,
            message=message,
            type_=type_,
        )
    except Exception:  # notifications are best-effort
        logger.exception("In-app notification failed for %s", user_id)


async def send_credentials_email(
    db: Any,
    *,
    to_email: str | None,
    recipient_name: str,
    temp_password: str,
    login_hint: str,
    shop_name: str | None = None,
    store_id: str | None = None,
    user_id: str | None = None,
    reason: str = "Your pharmacy account has been created",
) -> dict[str, Any]:
    """Send the temporary login credentials to a newly created or reset owner."""
    return await send_email(
        db,
        to_email=to_email,
        template="credentials",
        recipient_name=recipient_name,
        recipient_user_id=user_id,
        store_id=store_id,
        notify=True,
        notify_type="CREDENTIALS",
        notify_title="Your login details are ready",
        notify_message="We emailed your temporary password to your registered address.",
        context={
            "recipient_name": recipient_name,
            "temp_password": temp_password,
            "login_hint": login_hint,
            "shop_name": shop_name,
            "reason": reason,
        },
    )


async def send_first_login_email(
    db: Any,
    *,
    to_email: str | None,
    recipient_name: str,
    shop_name: str | None = None,
    store_id: str | None = None,
    user_id: str | None = None,
) -> dict[str, Any]:
    """Welcome email sent the first time an owner signs in."""
    return await send_email(
        db,
        to_email=to_email,
        template="first_login",
        recipient_name=recipient_name,
        recipient_user_id=user_id,
        store_id=store_id,
        notify=True,
        notify_type="WELCOME",
        notify_title="Welcome to MediShop",
        notify_message="Your account is active. Here is a quick look at what you can do.",
        context={"recipient_name": recipient_name, "shop_name": shop_name},
    )


async def send_action_required_email(
    db: Any,
    *,
    to_email: str | None,
    recipient_name: str,
    action_title: str,
    action_message: str,
    shop_name: str | None = None,
    store_id: str | None = None,
    user_id: str | None = None,
) -> dict[str, Any]:
    """Tell a user that one step is blocking them."""
    return await send_email(
        db,
        to_email=to_email,
        template="action_required",
        recipient_name=recipient_name,
        recipient_user_id=user_id,
        store_id=store_id,
        action_required=True,
        notify=True,
        notify_type="ACTION",
        notify_title=action_title,
        notify_message=action_message,
        context={
            "recipient_name": recipient_name,
            "action_title": action_title,
            "action_message": action_message,
            "shop_name": shop_name,
        },
    )


async def send_pending_action_emails(
    db: Any,
    *,
    user: dict[str, Any],
) -> list[dict[str, Any]]:
    """Email every step the signed-in user still has to complete.

    The pending list comes from the notifications module, so the emails, the
    in-app banner and the popup always agree. A step is mailed at most once
    a day, so signing in repeatedly never floods the inbox.
    """
    from app.modules.notifications import service as notifications

    user_id = str(user.get("sub") or "")
    if not user_id:
        return []

    pool = await get_pg_connection(db)
    row = await pool.fetchrow("SELECT * FROM users WHERE id = $1", user_id)
    if row is None:
        return []

    actions = await notifications.action_required(db, user)
    if not actions:
        return []

    store_id = str(row["owner_store_id"] or "") or None
    shop_name: str | None = None
    if store_id:
        shop_row = await pool.fetchrow(
            "SELECT shop_name FROM shops WHERE id = $1", store_id
        )
        shop_name = str(shop_row["shop_name"]) if shop_row else None

    results: list[dict[str, Any]] = []
    for action in actions:
        title = str(action.get("title") or "Action required")
        message = str(action.get("message") or "Complete this step to continue.")
        subject = f"Action required: {title}"
        already_sent = await pool.fetchrow(
            """SELECT id FROM email_logs
               WHERE recipient_user_id = $1
                 AND template = 'action_required'
                 AND subject = $2
                 AND created_at > NOW() - INTERVAL '24 hours'
               LIMIT 1""",
            user_id,
            subject,
        )
        if already_sent:
            continue
        results.append(
            await send_action_required_email(
                db,
                to_email=row["email_normalized"],
                recipient_name=str(row["full_name"] or "there"),
                action_title=title,
                action_message=message,
                shop_name=shop_name,
                store_id=store_id,
                user_id=user_id,
            )
        )
    return results


async def send_issue_raised_email(
    db: Any,
    *,
    to_email: str | None,
    issue_title: str,
    issue_category: str,
    issue_description: str,
    shop_name: str | None = None,
    owner_name: str | None = None,
    store_id: str | None = None,
) -> dict[str, Any]:
    """Alert the support team that an owner raised an issue."""
    return await send_email(
        db,
        to_email=to_email,
        template="issue_raised",
        recipient_name="Support team",
        store_id=store_id,
        notify=False,
        context={
            "issue_title": issue_title,
            "issue_category": issue_category,
            "issue_description": issue_description,
            "shop_name": shop_name,
            "owner_name": owner_name,
        },
    )


async def send_issue_status_email(
    db: Any,
    *,
    to_email: str | None,
    recipient_name: str | None,
    issue_title: str,
    issue_status: str,
    issue_note: str | None = None,
    shop_name: str | None = None,
    store_id: str | None = None,
    user_id: str | None = None,
) -> dict[str, Any]:
    """Tell the owner that their issue moved to a new status."""
    return await send_email(
        db,
        to_email=to_email,
        template="issue_status",
        recipient_name=recipient_name,
        recipient_user_id=user_id,
        store_id=store_id,
        notify=True,
        notify_type="ISSUE",
        notify_title=f"Issue {issue_status.replace('_', ' ').lower()}",
        notify_message=f"Your report '{issue_title}' is now {issue_status}.",
        context={
            "issue_title": issue_title,
            "issue_status": issue_status,
            "issue_note": issue_note,
            "shop_name": shop_name,
        },
    )


async def send_test_email(db: Any, *, to_email: str, user_id: str | None = None) -> dict[str, Any]:
    """Send a test message so the admin can verify SMTP settings."""
    return await send_email(
        db,
        to_email=to_email,
        template="test",
        recipient_name="MediShop admin",
        recipient_user_id=user_id,
        context={"sent_at": datetime.now(timezone.utc).isoformat(timespec="seconds")},
    )


async def list_email_logs(
    db: Any,
    *,
    user: dict[str, Any],
    status: str | None = None,
    template: str | None = None,
    limit: int = 100,
) -> list[dict[str, Any]]:
    """Admins see every email; owners only see the ones addressed to them."""
    pool = await get_pg_connection(db)
    conditions: list[str] = []
    args: list[Any] = []
    if user.get("role") != "SUPER_ADMIN":
        args.append(str(user.get("sub") or ""))
        args.append(str(user.get("storeId") or ""))
        conditions.append(
            "(recipient_user_id::text = ${0} OR (store_id IS NOT NULL AND store_id::text = ${1}))".format(
                len(args) - 1, len(args)
            )
        )
    if status:
        args.append(status.upper())
        conditions.append(f"status = ${len(args)}")
    if template:
        args.append(template)
        conditions.append(f"template = ${len(args)}")
    query = "SELECT * FROM email_logs"
    if conditions:
        query += " WHERE " + " AND ".join(conditions)
    args.append(min(max(limit, 1), 200))
    query += " ORDER BY created_at DESC LIMIT $" + str(len(args))
    rows = await pool.fetch(query, *args)
    return [dict(row) for row in rows]


async def find_email_log(db: Any, log_id: str) -> dict[str, Any] | None:
    pool = await get_pg_connection(db)
    row = await pool.fetchrow(
        "SELECT * FROM email_logs WHERE id = $1", _as_uuid(log_id)
    )
    return dict(row) if row else None


async def resend_email(db: Any, log: dict[str, Any]) -> dict[str, Any]:
    """Send a stored email again using the body that was originally built."""
    settings = get_settings()
    recipient = str(log.get("recipient_email") or "")
    if not recipient:
        return {**log, "status": STATUS_SKIPPED, "error_message": "No email address on file"}

    subject = str(log.get("subject") or "MediShop notification")
    body_text = str(log.get("body_text") or subject)

    if not settings.mail_enabled:
        await _update_status(
            db,
            str(log["id"]),
            status=STATUS_SKIPPED,
            error_message="SMTP is not configured (set SMTP_HOST and SMTP_FROM_EMAIL)",
        )
        return {**log, "status": STATUS_SKIPPED}

    message = EmailMessage()
    message["Subject"] = subject
    message["From"] = formataddr((settings.smtp_from_name, settings.smtp_from_email))
    message["To"] = recipient
    message.set_content(body_text)
    try:
        await asyncio.to_thread(_deliver_via_smtp, settings, message)
    except Exception as error:  # noqa: BLE001
        detail = f"{type(error).__name__}: {error}"
        await _update_status(db, str(log["id"]), status=STATUS_FAILED, error_message=detail)
        return {**log, "status": STATUS_FAILED, "error_message": detail}

    await _update_status(
        db,
        str(log["id"]),
        status=STATUS_SENT,
        error_message=None,
        sent_at=datetime.now(timezone.utc),
    )
    return {**log, "status": STATUS_SENT, "error_message": None}


def smtp_status() -> dict[str, Any]:
    """Non-secret view of the SMTP configuration for the settings screen."""
    settings = get_settings()
    return {
        "configured": settings.smtp_configured,
        "enabled": settings.mail_enabled,
        "host": settings.smtp_host or "",
        "port": settings.smtp_port,
        "username": settings.smtp_username or "",
        "fromEmail": settings.smtp_from_email or "",
        "fromName": settings.smtp_from_name,
        "useTls": settings.smtp_use_tls,
        "useSsl": settings.smtp_use_ssl,
        "appBaseUrl": settings.app_base_url,
        "supportEmail": settings.support_email,
        "templates": templates.available_templates(),
    }
