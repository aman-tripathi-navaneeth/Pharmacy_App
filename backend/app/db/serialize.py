from datetime import date, datetime, timezone
from decimal import Decimal
from typing import Any
from uuid import UUID

import re

_CAMEL_RE = re.compile(r"_([a-z0-9])")


def _camel(key: str) -> str:
    """Convert a snake_case database column name to the camelCase API contract."""
    if key.startswith("_"):
        return key
    return _CAMEL_RE.sub(lambda match: match.group(1).upper(), key)


def to_str(value: Any) -> str | None:
    """Convert an ID to string, handling UUIDs and other types."""
    if value is None:
        return None
    if isinstance(value, str):
        return value
    return str(value)


def serialize(value: Any) -> Any:
    """Convert Python/DB values into the JSON shapes the Flutter app expects."""
    if isinstance(value, datetime):
        if value.tzinfo is None:
            value = value.replace(tzinfo=timezone.utc)
        return value.astimezone(timezone.utc).isoformat(timespec="milliseconds").replace("+00:00", "Z")
    if isinstance(value, date):
        return value.isoformat()
    if isinstance(value, Decimal):
        return float(value)
    if isinstance(value, (UUID,)):
        return str(value)
    if isinstance(value, dict):
        result: dict[str, Any] = {}
        for key, item in value.items():
            result[_camel(str(key))] = serialize(item)
        # Preserve the identifier shape expected by existing Flutter screens.
        if "id" in result and "_id" not in result and result["id"] is not None:
            result["_id"] = str(result["id"])
        return result
    if isinstance(value, (list, tuple)):
        return [serialize(item) for item in value]
    return value
