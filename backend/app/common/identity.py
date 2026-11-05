import re

_EMAIL_RE = re.compile(r"^[^\s@]+@[^\s@]+\.[^\s@]+$")
_PHONE_RE = re.compile(r"^[0-9]{10,13}$")


def normalize_email(value: str) -> str:
    return value.strip().lower()


def normalize_phone(value: str) -> str:
    digits = re.sub(r"\D", "", value)
    if len(digits) == 10:
        return f"+91{digits}"
    if len(digits) == 12 and digits.startswith("91"):
        return f"+{digits}"
    if len(digits) == 13 and digits.startswith("91"):
        return f"+91{digits[3:]}"
    return f"+{digits}"


def is_probably_email(value: str) -> bool:
    return bool(_EMAIL_RE.match(value.strip()))


def is_valid_contact(value: str) -> bool:
    raw = value.strip()
    if not raw:
        return False
    if "@" in raw:
        return bool(_EMAIL_RE.match(raw))
    return bool(_PHONE_RE.match(re.sub(r"\D", "", raw)))


def mask_destination(destination: str) -> str:
    if is_probably_email(destination):
        local, _, domain = destination.partition("@")
        masked = local[:2] + "***" + local[-1:]
        return f"{masked}@{domain}"
    if len(destination) > 4:
        return f"+91-xxxxx-{normalize_phone(destination)[-4:]}"
    return "your registered contact"
