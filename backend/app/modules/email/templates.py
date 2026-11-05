"""Plain-text and HTML templates for every transactional email.

Each template is a small function that returns a ``RenderedEmail`` with a
subject, an HTML body and a plain-text fallback. Templates never raise for
missing context keys - unknown values render as an empty string so a partial
context can never break an email.
"""

from dataclasses import dataclass, field
from typing import Any

BRAND = "MediShop"
BRAND_COLOR = "#0B4F3A"


@dataclass
class RenderedEmail:
    template: str
    subject: str
    html: str
    text: str
    preview: str = field(default="", repr=False)


def _value(context: dict[str, Any], key: str, default: str = "") -> str:
    raw = context.get(key, default)
    if raw is None:
        return default
    return str(raw).strip()


def _escape(value: str) -> str:
    return (
        value.replace("&", "&amp;")
        .replace("<", "&lt;")
        .replace(">", "&gt;")
        .replace('"', "&quot;")
    )


def _layout(title: str, intro: str, blocks: list[tuple[str, str]], cta: tuple[str, str] | None) -> tuple[str, str]:
    """Build the shared HTML shell and its plain-text twin."""
    html_blocks = []
    for heading, body in blocks:
        html_blocks.append(
            "<tr><td style=\"padding:8px 0\">"
            f"<div style=\"font-weight:700;color:{BRAND_COLOR};font-size:13px;text-transform:uppercase;letter-spacing:.04em\">{_escape(heading)}</div>"
            f"<div style=\"color:#1E293B;font-size:15px;line-height:1.5\">{_escape(body)}</div>"
            "</td></tr>"
        )
    cta_html = ""
    if cta:
        label, url = cta
        cta_html = (
            "<tr><td style=\"padding:16px 0\">"
            f"<a href=\"{_escape(url)}\" style=\"display:inline-block;background:{BRAND_COLOR};color:#ffffff;"
            "padding:12px 20px;border-radius:8px;text-decoration:none;font-weight:600\">"
            f"{_escape(label)}</a>"
            f"<div style=\"color:#64748B;font-size:12px;margin-top:8px\">{_escape(url)}</div>"
            "</td></tr>"
        )
    html = f"""<!doctype html>
<html>
  <body style="margin:0;padding:24px;background:#F1F5F9;font-family:Segoe UI,Roboto,Helvetica,Arial,sans-serif;color:#1E293B">
    <table role="presentation" width="100%" cellpadding="0" cellspacing="0">
      <tr><td align="center">
        <table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="max-width:560px;background:#ffffff;border-radius:14px;border:1px solid #E2E8F0">
          <tr><td style="padding:24px 24px 8px">
            <div style="font-size:18px;font-weight:800;color:{BRAND_COLOR}">{BRAND}</div>
            <h1 style="font-size:22px;margin:8px 0 0">{_escape(title)}</h1>
          </td></tr>
          <tr><td style="padding:0 24px">
            <p style="font-size:15px;line-height:1.6;color:#334155">{_escape(intro)}</p>
          </td></tr>
          <tr><td style="padding:8px 24px">
            <table role="presentation" width="100%" cellpadding="0" cellspacing="0">
              {''.join(html_blocks)}
            </table>
          </td></tr>
          {cta_html}
          <tr><td style="padding:16px 24px 24px;border-top:1px solid #E2E8F0;color:#64748B;font-size:12px">
            This message was sent automatically by {BRAND}. If you did not expect it, ignore this email.
          </td></tr>
        </table>
      </td></tr>
    </table>
  </body>
</html>"""

    text_lines = [title, "", intro, ""]
    for heading, body in blocks:
        text_lines.extend([heading.upper(), body, ""])
    if cta:
        text_lines.extend([cta[0], cta[1], ""])
    text_lines.append(f"This message was sent automatically by {BRAND}.")
    return html, "\n".join(text_lines)


def _credentials(context: dict[str, Any]) -> RenderedEmail:
    name = _value(context, "recipient_name", "there")
    shop = _value(context, "shop_name", "your pharmacy")
    temp_password = _value(context, "temp_password")
    login_hint = _value(context, "login_hint")
    reason = _value(context, "reason", "Your pharmacy account has been created")
    app_url = _value(context, "app_url", "http://127.0.0.1:8000")
    support = _value(context, "support_email")
    subject = f"Your {shop} login details"
    intro = f"Hi {name}, {reason}. Use the temporary password below to sign in to the app."
    blocks = [
        ("Temporary password", temp_password),
        ("Sign in with", login_hint),
    ]
    if support:
        blocks.append(("Need help?", f"Contact the support team at {support}."))
    html, text = _layout(subject, intro, blocks, ("Open MediShop", app_url))
    return RenderedEmail("credentials", subject, html, text, preview=temp_password)


def _first_login(context: dict[str, Any]) -> RenderedEmail:
    name = _value(context, "recipient_name", "there")
    shop = _value(context, "shop_name", "your pharmacy")
    app_url = _value(context, "app_url", "http://127.0.0.1:8000")
    subject = f"Welcome to {BRAND}, {name}"
    intro = (
        f"Your {shop} account is active and this was your first sign-in. "
        "Everything you need to run the counter is inside the app."
    )
    blocks = [
        ("What you can do", "Add stock, raise bills, track udhaar and share prescriptions."),
        ("Stay in control", "Every bill, payment and stock change is saved in history you can revisit."),
    ]
    html, text = _layout(subject, intro, blocks, ("Open the app", app_url))
    return RenderedEmail("first_login", subject, html, text)


def _action_required(context: dict[str, Any]) -> RenderedEmail:
    name = _value(context, "recipient_name", "there")
    shop = _value(context, "shop_name", "your pharmacy")
    action_title = _value(context, "action_title", "Action required")
    action_message = _value(context, "action_message")
    app_url = _value(context, "app_url", "http://127.0.0.1:8000")
    subject = f"Action required: {action_title}"
    intro = f"Hi {name}, your {shop} account needs one step completed before you can continue."
    blocks = [("What to do", action_message)]
    html, text = _layout(subject, intro, blocks, ("Open MediShop", app_url))
    return RenderedEmail("action_required", subject, html, text)


def _issue_raised(context: dict[str, Any]) -> RenderedEmail:
    title = _value(context, "issue_title", "An issue was reported")
    category = _value(context, "issue_category", "OTHER")
    shop = _value(context, "shop_name", "A pharmacy")
    owner = _value(context, "owner_name", "A shop owner")
    description = _value(context, "issue_description")
    app_url = _value(context, "app_url", "http://127.0.0.1:8000")
    subject = f"New issue raised: {title}"
    intro = f"{owner} from {shop} raised a {category.lower().replace('_', ' ')} issue that needs review."
    blocks = [("Issue", title), ("Details", description)]
    html, text = _layout(subject, intro, blocks, ("Review the issue", app_url))
    return RenderedEmail("issue_raised", subject, html, text)


def _issue_status(context: dict[str, Any]) -> RenderedEmail:
    title = _value(context, "issue_title", "Your issue")
    status = _value(context, "issue_status", "RESOLVED")
    note = _value(context, "issue_note") or "No additional note was added."
    shop = _value(context, "shop_name", "your pharmacy")
    app_url = _value(context, "app_url", "http://127.0.0.1:8000")
    subject = f"Your issue '{title}' is now {status.replace('_', ' ').lower()}"
    intro = f"The support team updated the status of your report for {shop}."
    blocks = [("Status", status.replace("_", " ").title()), ("Note from support", note)]
    html, text = _layout(subject, intro, blocks, ("Open the app", app_url))
    return RenderedEmail("issue_status", subject, html, text)


def _test(context: dict[str, Any]) -> RenderedEmail:
    app_url = _value(context, "app_url", "http://127.0.0.1:8000")
    subject = f"{BRAND} email test"
    intro = "This is a test message from your MediShop server. SMTP delivery is working."
    blocks = [("Sent at", _value(context, "sent_at", "now"))]
    html, text = _layout(subject, intro, blocks, ("Open MediShop", app_url))
    return RenderedEmail("test", subject, html, text)


_RENDERERS = {
    "credentials": _credentials,
    "first_login": _first_login,
    "action_required": _action_required,
    "issue_raised": _issue_raised,
    "issue_status": _issue_status,
    "test": _test,
}


def render(template: str, context: dict[str, Any] | None = None) -> RenderedEmail:
    """Render a template by name. Unknown templates fall back to the test mail."""
    renderer = _RENDERERS.get(template, _test)
    return renderer(context or {})


def available_templates() -> list[str]:
    """Template names the API can trigger, for the email history screen."""
    return sorted(_RENDERERS)
