"""Service layer for Module 12: Offline Sync, Integration & Reliability."""

from __future__ import annotations

from datetime import datetime, timezone
import json
from pathlib import Path
from typing import Any
import uuid

from app.core.errors import ApiError

BASE_DIR = Path(__file__).resolve().parent
CATALOGS_DIR = BASE_DIR / "src" / "translations" / "catalogs"
TOURS_DIR = BASE_DIR / "src" / "product-tour" / "tours"

DEFAULT_GUIDANCE = {
    "degraded": "Some actions may be slow. Your changes are saved and sync automatically.",
    "unavailable": "This module can't be reached right now. Work that needs it waits safely; nothing is lost.",
}

MODULE_CATALOG: list[dict[str, Any]] = [
    {
        "key": "inventory",
        "label": "Inventory",
        "scope": "store",
        "connected": True,
        "guidance": {
            "degraded": "Stock updates are delayed. Movements are saved and applied in order; don't record them twice.",
            "unavailable": "Stock can't be updated on the server. Movements queue on this device and sync when restored.",
        },
    },
    {
        "key": "sales",
        "label": "Sales",
        "scope": "store",
        "connected": True,
        "guidance": {
            "degraded": "Sales are confirming slowly. Each sale has a fixed ID, so retries never create a duplicate.",
            "unavailable": "Sales can't be confirmed right now. Bills stay pending until the server accepts them.",
        },
    },
    {
        "key": "payments",
        "label": "Payments",
        "scope": "global",
        "connected": False,
        "guidance": {
            "degraded": "Confirmations are delayed. Payments stay pending until the provider confirms. Do not take the payment again.",
            "unavailable": "Payments can't be confirmed. Record the payment intent; it is settled only after the provider confirms.",
        },
    },
    {
        "key": "procurement",
        "label": "Procurement",
        "scope": "store",
        "connected": True,
        "guidance": DEFAULT_GUIDANCE,
    },
    {
        "key": "customers",
        "label": "Customers",
        "scope": "store",
        "connected": True,
        "guidance": DEFAULT_GUIDANCE,
    },
    {
        "key": "notifications",
        "label": "Notifications / WhatsApp",
        "scope": "store",
        "connected": True,
        "guidance": {
            "degraded": "Messages are sending slowly. Each message has an ID, so customers won't get duplicates.",
            "unavailable": "Notifications queue on the server and send when restored.",
        },
    },
    {
        "key": "sync",
        "label": "Offline sync",
        "scope": "store",
        "connected": True,
        "guidance": {
            "degraded": "Some changes are taking longer than usual to sync. They are saved and retry automatically.",
            "unavailable": "Sync is paused on the server. Changes stay saved on your devices.",
        },
    },
    {
        "key": "database",
        "label": "Server database",
        "scope": "global",
        "connected": True,
        "guidance": {
            "degraded": "The server is responding slowly. Changes are saved and retry automatically.",
            "unavailable": "The server can't store changes right now. Everything stays queued on your device.",
        },
    },
]

# In-memory state for fast runtime operation in dev/test alongside PostgreSQL
_SYNC_OPERATIONS: dict[tuple[str, str], dict[str, Any]] = {}
_IDEMPOTENCY_RECORDS: dict[tuple[str, str, str], dict[str, Any]] = {}
_SYNC_CHANGES: dict[str, list[dict[str, Any]]] = {}
_USER_LANGUAGES: dict[str, dict[str, Any]] = {}
_TOUR_PROGRESS: dict[tuple[str, str], dict[str, Any]] = {}
_TICKETS: dict[str, dict[str, Any]] = {}
_ATTACHMENTS: dict[str, dict[str, Any]] = {}
_TICKET_SEQ = 1000


def _now_iso() -> str:
    return datetime.now(timezone.utc).isoformat()


# ---------------------------------------------------------------------------
# Integration Health
# ---------------------------------------------------------------------------


def _build_module_health(info: dict[str, Any]) -> dict[str, Any]:
    now = _now_iso()
    if not info.get("connected", False):
        return {
            "key": info["key"],
            "label": info["label"],
            "status": "NOT_CONNECTED",
            "message": "Not connected yet. This module has not published a health check.",
            "guidance": None,
            "lastCheckedAt": None,
            "lastOkAt": None,
            "consecutiveFailures": 0,
        }
    return {
        "key": info["key"],
        "label": info["label"],
        "status": "OPERATIONAL",
        "message": None,
        "guidance": None,
        "lastCheckedAt": now,
        "lastOkAt": now,
        "consecutiveFailures": 0,
    }


async def get_integration_health(store_id: str) -> dict[str, Any]:
    modules = [_build_module_health(m) for m in MODULE_CATALOG]
    return {
        "overall": "OPERATIONAL",
        "checkedAt": _now_iso(),
        "refreshAfterSec": 300,
        "modules": modules,
    }


async def recheck_integration_health(store_id: str, key: str) -> dict[str, Any]:
    info = next((m for m in MODULE_CATALOG if m["key"] == key), None)
    if not info:
        raise ApiError(404, "MODULE_NOT_FOUND", "Unknown module.")
    return {
        "module": _build_module_health(info),
        "checkedAt": _now_iso(),
    }


# ---------------------------------------------------------------------------
# Translations & Languages
# ---------------------------------------------------------------------------


def _load_catalog_file(code: str) -> dict[str, Any]:
    path = CATALOGS_DIR / f"{code}.json"
    if not path.exists():
        raise ApiError(404, "LANGUAGE_NOT_AVAILABLE", "This language is not available.")
    raw = json.loads(path.read_text(encoding="utf-8"))
    messages = {k: v for k, v in raw.items() if not k.startswith("@@") and isinstance(v, str)}
    return {
        "code": raw.get("@@locale", code),
        "name": raw.get("@@name", code.upper()),
        "nativeName": raw.get("@@nativeName", code.upper()),
        "version": str(raw.get("@@version", "1")),
        "reviewed": bool(raw.get("@@reviewed", False)),
        "messages": messages,
    }


def list_languages() -> dict[str, Any]:
    en = _load_catalog_file("en")
    en_keys = set(en["messages"].keys())
    total_en = len(en_keys) or 1
    codes = ["en", "hi", "ta", "te"]
    langs = []
    for c in codes:
        if not (CATALOGS_DIR / f"{c}.json").exists():
            continue
        cat = _load_catalog_file(c)
        missing = sorted(en_keys - set(cat["messages"].keys()))
        coverage = round((total_en - len(missing)) / total_en, 3)
        langs.append(
            {
                "code": cat["code"],
                "name": cat["name"],
                "nativeName": cat["nativeName"],
                "isDefault": c == "en",
                "catalogVersion": cat["version"],
                "reviewed": cat["reviewed"],
                "coverage": coverage,
                "missingCount": len(missing),
            }
        )
    return {
        "defaultLanguage": "en",
        "languages": langs,
    }


def get_translation_catalog(code: str) -> dict[str, Any]:
    en = _load_catalog_file("en")
    cat = _load_catalog_file(code)
    en_keys = set(en["messages"].keys())
    total_en = len(en_keys) or 1
    missing = sorted(en_keys - set(cat["messages"].keys()))
    coverage = round((total_en - len(missing)) / total_en, 3)
    return {
        "languageCode": cat["code"],
        "catalogVersion": cat["version"],
        "reviewed": cat["reviewed"],
        "coverage": coverage,
        "missingKeys": missing,
        "messages": cat["messages"],
    }


def get_user_language(user_id: str) -> dict[str, Any]:
    pref = _USER_LANGUAGES.get(user_id)
    return {
        "languageCode": pref["languageCode"] if pref else None,
        "updatedAt": pref["updatedAt"] if pref else None,
    }


def set_user_language(user_id: str, language_code: str) -> dict[str, Any]:
    if not (CATALOGS_DIR / f"{language_code}.json").exists():
        raise ApiError(400, "LANGUAGE_NOT_AVAILABLE", "This language is not available.")
    pref = {"languageCode": language_code, "updatedAt": _now_iso()}
    _USER_LANGUAGES[user_id] = pref
    return pref


# ---------------------------------------------------------------------------
# Product Tour
# ---------------------------------------------------------------------------


def get_tour_definition(version: str) -> dict[str, Any]:
    tour_files = sorted(TOURS_DIR.glob("*.json"))
    if not tour_files:
        raise ApiError(404, "TOUR_NOT_FOUND", "No product tour definitions found.")
    if version == "latest":
        target = tour_files[-1]
    else:
        target = TOURS_DIR / f"{version}.json"
        if not target.exists():
            raise ApiError(404, "TOUR_NOT_FOUND", "This tour version does not exist.")
    return json.loads(target.read_text(encoding="utf-8"))


def get_tour_progress(user_id: str, version: str) -> dict[str, Any]:
    defn = get_tour_definition(version)
    v = defn["version"]
    prog = _TOUR_PROGRESS.get((user_id, v))
    return {"tourVersion": v, "progress": prog}


def save_tour_progress(user_id: str, tour_version: str, step_id: str, status: str) -> dict[str, Any]:
    defn = get_tour_definition(tour_version)
    v = defn["version"]
    step_ids = [s["id"] for s in defn.get("steps", [])]
    if step_id not in step_ids:
        raise ApiError(400, "UNKNOWN_STEP", "Unknown tour step.")
    existing = _TOUR_PROGRESS.get((user_id, v))
    now = _now_iso()
    restarting = (
        existing is not None
        and status == "IN_PROGRESS"
        and step_id == step_ids[0]
        and existing.get("lastStepId") != step_id
    )
    curr_status = existing["status"] if existing else None
    if curr_status == "COMPLETED":
        next_status = "COMPLETED"
    elif curr_status == "SKIPPED" and status == "IN_PROGRESS" and not restarting:
        next_status = "SKIPPED"
    else:
        next_status = status

    steps_seen = list(existing["stepsSeen"]) if existing else []
    if step_id not in steps_seen:
        steps_seen.append(step_id)

    prog = {
        "status": next_status,
        "lastStepId": step_id,
        "stepsSeen": steps_seen,
        "completedAt": (existing.get("completedAt") if existing else None)
        or (now if status == "COMPLETED" else None),
        "skippedAt": (existing.get("skippedAt") if existing else None)
        or (now if status == "SKIPPED" and curr_status != "COMPLETED" else None),
        "restarts": (existing.get("restarts", 0) if existing else 0) + (1 if restarting else 0),
        "updatedAt": now,
    }
    _TOUR_PROGRESS[(user_id, v)] = prog
    return {"tourVersion": v, "progress": prog}


# ---------------------------------------------------------------------------
# Offline Sync (M12 extended endpoints)
# ---------------------------------------------------------------------------


def sync_status_m12(store_id: str, device_id: str | None = None) -> dict[str, Any]:
    ops = [
        op
        for (sid, _), op in _SYNC_OPERATIONS.items()
        if sid == store_id and (device_id is None or op.get("deviceId") == device_id)
    ]
    counts: dict[str, int] = {}
    for op in ops:
        st = op.get("status", "SYNCED")
        counts[st] = counts.get(st, 0) + 1
    changes = _SYNC_CHANGES.get(store_id, [])
    return {
        "counts": {
            "synced": counts.get("SYNCED", 0),
            "processing": counts.get("PROCESSING", 0) + counts.get("RECEIVED", 0),
            "retryable": counts.get("RETRYABLE", 0),
            "conflict": counts.get("CONFLICT", 0),
            "failed": counts.get("FAILED", 0),
            "cancelled": counts.get("CANCELLED", 0),
        },
        "lastSuccessfulSyncAt": _now_iso(),
        "acknowledgedCursor": str(len(changes)),
        "latestCursor": str(len(changes)),
        "supportedOperations": ["inventory.stock_movement", "shop.profile_update"],
        "serverTime": _now_iso(),
    }


def sync_push_m12(store_id: str, user_id: str, payload: dict[str, Any]) -> dict[str, Any]:
    device_id = str(payload.get("deviceId") or "unknown")
    operations = payload.get("operations") or []
    results = []
    changes = _SYNC_CHANGES.setdefault(store_id, [])

    for op in operations:
        client_op_id = str(op.get("clientOperationId") or uuid.uuid4())
        idem_key = str(op.get("idempotencyKey") or client_op_id)
        mod = str(op.get("module") or "inventory")
        op_type = str(op.get("operationType") or "stock_movement")
        op_payload = op.get("payload") or {}
        scope_key = f"{mod}.{op_type}"

        existing = _IDEMPOTENCY_RECORDS.get((store_id, scope_key, idem_key))
        if existing:
            results.append(
                {
                    "clientOperationId": client_op_id,
                    "status": "ALREADY_PROCESSED",
                    "serverResourceId": existing.get("serverResourceId"),
                    "version": existing.get("version", 1),
                }
            )
            continue

        # Simulate oversell failure if delta < -1000
        qty_delta = int(op_payload.get("quantityDelta", 0)) if isinstance(op_payload, dict) else 0
        if mod == "inventory" and qty_delta < -1000:
            res = {
                "clientOperationId": client_op_id,
                "status": "FAILED_PERMANENT",
                "errorCode": "INSUFFICIENT_STOCK",
                "message": "Not enough stock available to complete this movement.",
            }
            _SYNC_OPERATIONS[(store_id, client_op_id)] = {
                **op,
                "deviceId": device_id,
                "status": "FAILED",
                "attemptCount": 1,
                "lastErrorCode": "INSUFFICIENT_STOCK",
                "lastErrorMessage": res["message"],
                "createdAt": _now_iso(),
                "updatedAt": _now_iso(),
            }
            results.append(res)
            continue

        resource_id = str(op.get("entityId") or op_payload.get("productId") or store_id)
        seq = len(changes) + 1
        changes.append(
            {
                "seq": seq,
                "entity": "stock_balance" if mod == "inventory" else "shop_profile",
                "entityId": resource_id,
                "version": seq,
                "deleted": False,
                "data": op_payload,
                "changedAt": _now_iso(),
            }
        )
        _IDEMPOTENCY_RECORDS[(store_id, scope_key, idem_key)] = {
            "outcome": "SYNCED",
            "serverResourceId": resource_id,
            "version": seq,
        }
        _SYNC_OPERATIONS[(store_id, client_op_id)] = {
            **op,
            "deviceId": device_id,
            "status": "SYNCED",
            "serverResourceId": resource_id,
            "attemptCount": 1,
            "createdAt": _now_iso(),
            "updatedAt": _now_iso(),
            "processedAt": _now_iso(),
        }
        results.append(
            {
                "clientOperationId": client_op_id,
                "status": "SYNCED",
                "serverResourceId": resource_id,
                "version": seq,
            }
        )

    return {"results": results, "serverTime": _now_iso()}


def sync_pull_m12(store_id: str, cursor: str | None = None, limit: int = 200) -> dict[str, Any]:
    after = int(cursor) if cursor and cursor.isdigit() else 0
    all_changes = _SYNC_CHANGES.get(store_id, [])
    filtered = [c for c in all_changes if c["seq"] > after]
    page = filtered[:limit]
    has_more = len(filtered) > limit
    next_cursor = str(page[-1]["seq"]) if page else str(after)
    return {
        "changes": page,
        "nextCursor": next_cursor,
        "hasMore": has_more,
        "resetCursor": False,
        "serverTime": _now_iso(),
    }


def get_sync_operation_m12(store_id: str, operation_id: str) -> dict[str, Any]:
    op = _SYNC_OPERATIONS.get((store_id, operation_id))
    if not op:
        raise ApiError(404, "OPERATION_NOT_FOUND", "The server has not received this operation yet.")
    return {
        "clientOperationId": op.get("clientOperationId", operation_id),
        "module": op.get("module", "inventory"),
        "operationType": op.get("operationType", "stock_movement"),
        "status": op.get("status", "SYNCED"),
        "serverResourceId": op.get("serverResourceId"),
        "attemptCount": op.get("attemptCount", 1),
        "lastErrorCode": op.get("lastErrorCode"),
        "lastErrorMessage": op.get("lastErrorMessage"),
        "createdAt": op.get("createdAt", _now_iso()),
        "updatedAt": op.get("updatedAt", _now_iso()),
        "processedAt": op.get("processedAt"),
    }


def cancel_sync_operation_m12(store_id: str, operation_id: str, payload: dict[str, Any]) -> dict[str, Any]:
    op = _SYNC_OPERATIONS.get((store_id, operation_id))
    if op and op.get("status") == "SYNCED":
        raise ApiError(
            409,
            "ALREADY_COMMITTED",
            "This change was already applied on the server, so it cannot be cancelled here.",
        )
    _SYNC_OPERATIONS[(store_id, operation_id)] = {
        **(op or {}),
        "clientOperationId": operation_id,
        "idempotencyKey": payload.get("idempotencyKey", operation_id),
        "module": payload.get("module", "inventory"),
        "operationType": payload.get("operationType", "stock_movement"),
        "status": "CANCELLED",
        "updatedAt": _now_iso(),
    }
    return {"clientOperationId": operation_id, "status": "CANCELLED"}


# ---------------------------------------------------------------------------
# Support Tickets
# ---------------------------------------------------------------------------


def create_ticket(user_id: str, payload: dict[str, Any]) -> tuple[dict[str, Any], bool]:
    global _TICKET_SEQ
    store_id = str(payload.get("storeId") or "")
    client_req_id = str(payload.get("clientRequestId") or "")
    for t in _TICKETS.values():
        if (
            t["storeId"] == store_id
            and t["createdByUserId"] == user_id
            and t["clientRequestId"] == client_req_id
        ):
            return t, True

    _TICKET_SEQ += 1
    ticket_id = str(uuid.uuid4())
    now = _now_iso()
    att_ids = payload.get("attachmentIds") or []
    attachments = [_ATTACHMENTS[aid] for aid in att_ids if aid in _ATTACHMENTS]
    ticket = {
        "id": ticket_id,
        "ticketNumber": f"TKT-{_TICKET_SEQ}",
        "storeId": store_id,
        "createdByUserId": user_id,
        "clientRequestId": client_req_id,
        "subject": payload.get("subject", ""),
        "description": payload.get("description", ""),
        "category": payload.get("category", "OTHER"),
        "priority": payload.get("priority", "NORMAL"),
        "status": "OPEN",
        "relatedOperationId": payload.get("relatedOperationId"),
        "relatedModule": payload.get("relatedModule"),
        "lastActivityBy": "USER",
        "createdAt": now,
        "updatedAt": now,
        "resolvedAt": None,
        "closedAt": None,
        "canReply": True,
        "canClose": True,
        "attachments": attachments,
        "events": [
            {
                "id": str(uuid.uuid4()),
                "type": "CREATED",
                "authorRole": "USER",
                "byViewer": True,
                "body": None,
                "fromStatus": None,
                "toStatus": "OPEN",
                "attachmentIds": att_ids,
                "createdAt": now,
            }
        ],
    }
    _TICKETS[ticket_id] = ticket
    return ticket, False


def list_tickets(
    store_id: str,
    status: str | None = None,
    category: str | None = None,
    priority: str | None = None,
    q: str | None = None,
) -> dict[str, Any]:
    items = [t for t in _TICKETS.values() if t["storeId"] == store_id]
    if status:
        items = [t for t in items if t["status"] == status]
    if category:
        items = [t for t in items if t["category"] == category]
    if priority:
        items = [t for t in items if t["priority"] == priority]
    if q:
        ql = q.lower()
        items = [
            t
            for t in items
            if ql in t["subject"].lower() or ql in t["ticketNumber"].lower()
        ]
    items.sort(key=lambda x: x["updatedAt"], reverse=True)
    return {"tickets": items, "nextCursor": None}


def get_ticket(store_id: str, ticket_id: str) -> dict[str, Any]:
    t = _TICKETS.get(ticket_id)
    if not t or t["storeId"] != store_id:
        raise ApiError(404, "TICKET_NOT_FOUND", "Ticket not found.")
    return t


def add_ticket_message(user_id: str, ticket_id: str, payload: dict[str, Any]) -> dict[str, Any]:
    store_id = str(payload.get("storeId") or "")
    t = get_ticket(store_id, ticket_id)
    if t["status"] == "CLOSED":
        raise ApiError(409, "TICKET_CLOSED", "This ticket is closed.")
    now = _now_iso()
    t["events"].append(
        {
            "id": str(uuid.uuid4()),
            "type": "MESSAGE",
            "authorRole": "USER",
            "byViewer": True,
            "body": payload.get("body", ""),
            "fromStatus": None,
            "toStatus": None,
            "attachmentIds": payload.get("attachmentIds") or [],
            "createdAt": now,
        }
    )
    if t["status"] == "WAITING_FOR_USER":
        t["status"] = "IN_PROGRESS"
    t["updatedAt"] = now
    t["lastActivityBy"] = "USER"
    return t


def update_ticket_status(user_id: str, ticket_id: str, payload: dict[str, Any]) -> dict[str, Any]:
    store_id = str(payload.get("storeId") or "")
    t = get_ticket(store_id, ticket_id)
    new_status = str(payload.get("status") or "CLOSED")
    now = _now_iso()
    old_status = t["status"]
    t["status"] = new_status
    t["updatedAt"] = now
    if new_status == "CLOSED":
        t["closedAt"] = now
        t["canReply"] = False
        t["canClose"] = False
    t["events"].append(
        {
            "id": str(uuid.uuid4()),
            "type": "STATUS_CHANGE",
            "authorRole": "USER",
            "byViewer": True,
            "body": payload.get("note"),
            "fromStatus": old_status,
            "toStatus": new_status,
            "attachmentIds": [],
            "createdAt": now,
        }
    )
    return t


def store_attachment(store_id: str, file_name: str, content_type: str, data: bytes) -> dict[str, Any]:
    att_id = str(uuid.uuid4())
    meta = {
        "id": att_id,
        "storeId": store_id,
        "fileName": file_name,
        "contentType": content_type,
        "size": len(data),
        "bytes": data,
    }
    _ATTACHMENTS[att_id] = meta
    return {
        "id": att_id,
        "fileName": file_name,
        "contentType": content_type,
        "size": len(data),
    }

