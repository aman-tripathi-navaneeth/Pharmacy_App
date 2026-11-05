"""API router for Module 12: Offline Sync, Integration & Reliability."""

from __future__ import annotations

from typing import Any

from fastapi import APIRouter, Depends, File, Form, Header, Query, Response, UploadFile
from pydantic import BaseModel

from app.common.deps import get_current_user
from app.modules.offline_sync_reliability import service

router = APIRouter(tags=["Offline Sync, Integration & Reliability"])


class StoreCheckIn(BaseModel):
    storeId: str = "00000000-0000-4000-9000-000000000001"


class SetLanguageIn(BaseModel):
    languageCode: str


class SaveTourProgressIn(BaseModel):
    tourVersion: str
    stepId: str
    status: str


# ---------------------------------------------------------------------------
# Integration Health
# ---------------------------------------------------------------------------


@router.get("/integrations/health")
async def integration_health(
    storeId: str = Query(default="00000000-0000-4000-9000-000000000001"),
) -> Any:
    return await service.get_integration_health(storeId)


@router.post("/integrations/health/{key}/check")
async def integration_recheck(
    key: str,
    body: StoreCheckIn,
) -> Any:
    return await service.recheck_integration_health(body.storeId, key)


# ---------------------------------------------------------------------------
# Languages & Translations
# ---------------------------------------------------------------------------


@router.get("/languages")
async def list_languages() -> Any:
    return service.list_languages()


@router.get("/translations/{language}")
async def get_translations(
    language: str,
    response: Response,
    if_none_match: str | None = Header(default=None, alias="if-none-match"),
) -> Any:
    body = service.get_translation_catalog(language)
    etag = f'"{language}@{body["catalogVersion"]}"'
    response.headers["ETag"] = etag
    response.headers["Cache-Control"] = "public, max-age=300"
    if if_none_match == etag:
        response.status_code = 304
        return Response(status_code=304, headers={"ETag": etag})
    return body


@router.get("/users/me/language")
async def my_language(
    user: dict[str, Any] = Depends(get_current_user),
) -> Any:
    return service.get_user_language(str(user.get("sub") or "anonymous"))


@router.patch("/users/me/language")
async def set_my_language(
    body: SetLanguageIn,
    user: dict[str, Any] = Depends(get_current_user),
) -> Any:
    return service.set_user_language(
        str(user.get("sub") or "anonymous"),
        body.languageCode,
    )


# ---------------------------------------------------------------------------
# Product Tour
# ---------------------------------------------------------------------------


@router.get("/product-tour/progress")
async def tour_progress(
    version: str = Query(default="latest"),
    user: dict[str, Any] = Depends(get_current_user),
) -> Any:
    return service.get_tour_progress(str(user.get("sub") or "anonymous"), version)


@router.post("/product-tour/progress")
async def save_tour_progress(
    body: SaveTourProgressIn,
    user: dict[str, Any] = Depends(get_current_user),
) -> Any:
    return service.save_tour_progress(
        str(user.get("sub") or "anonymous"),
        body.tourVersion,
        body.stepId,
        body.status,
    )


@router.get("/product-tour/{version}")
async def get_tour(version: str) -> Any:
    return service.get_tour_definition(version)


# ---------------------------------------------------------------------------
# Offline Sync (M12 extended endpoints)
# ---------------------------------------------------------------------------


@router.get("/sync/status")
async def sync_status_endpoint(
    storeId: str = Query(default="00000000-0000-4000-9000-000000000001"),
    deviceId: str | None = Query(default=None),
) -> Any:
    return service.sync_status_m12(storeId, deviceId)


@router.get("/sync/pull")
async def sync_pull_endpoint(
    storeId: str = Query(default="00000000-0000-4000-9000-000000000001"),
    deviceId: str | None = Query(default=None),
    cursor: str | None = Query(default=None),
    limit: int = Query(default=200),
) -> Any:
    return service.sync_pull_m12(storeId, cursor=cursor, limit=limit)


@router.get("/sync/operations/{operation_id}")
async def sync_operation_detail(
    operation_id: str,
    storeId: str = Query(default="00000000-0000-4000-9000-000000000001"),
) -> Any:
    return service.get_sync_operation_m12(storeId, operation_id)


@router.post("/sync/operations/{operation_id}/retry")
async def sync_operation_retry(
    operation_id: str,
    payload: dict[str, Any],
) -> Any:
    store_id = str(payload.get("storeId") or "00000000-0000-4000-9000-000000000001")
    op = service.get_sync_operation_m12(store_id, operation_id)
    return {
        "clientOperationId": operation_id,
        "status": op.get("status", "SYNCED"),
        "serverResourceId": op.get("serverResourceId"),
        "version": 1,
    }


@router.post("/sync/operations/{operation_id}/cancel")
async def sync_operation_cancel(
    operation_id: str,
    payload: dict[str, Any],
) -> Any:
    store_id = str(payload.get("storeId") or "00000000-0000-4000-9000-000000000001")
    return service.cancel_sync_operation_m12(store_id, operation_id, payload)


# ---------------------------------------------------------------------------
# Support Tickets
# ---------------------------------------------------------------------------


@router.post("/tickets")
async def create_ticket_endpoint(
    payload: dict[str, Any],
    response: Response,
    user: dict[str, Any] = Depends(get_current_user),
) -> Any:
    ticket, duplicate = service.create_ticket(
        str(user.get("sub") or "anonymous"),
        payload,
    )
    response.status_code = 200 if duplicate else 201
    return ticket


@router.get("/tickets")
async def list_tickets_endpoint(
    storeId: str = Query(default="00000000-0000-4000-9000-000000000001"),
    status: str | None = Query(default=None),
    category: str | None = Query(default=None),
    priority: str | None = Query(default=None),
    q: str | None = Query(default=None),
) -> Any:
    return service.list_tickets(
        store_id=storeId,
        status=status,
        category=category,
        priority=priority,
        q=q,
    )


@router.post("/tickets/attachments")
async def upload_ticket_attachment(
    storeId: str = Form(default="00000000-0000-4000-9000-000000000001"),
    file: UploadFile = File(...),
) -> Any:
    data = await file.read()
    return service.store_attachment(
        store_id=storeId,
        file_name=file.filename or "attachment.bin",
        content_type=file.content_type or "application/octet-stream",
        data=data,
    )


@router.get("/tickets/{ticket_id}")
async def get_ticket_endpoint(
    ticket_id: str,
    storeId: str = Query(default="00000000-0000-4000-9000-000000000001"),
) -> Any:
    return service.get_ticket(storeId, ticket_id)


@router.post("/tickets/{ticket_id}/messages")
async def add_ticket_message_endpoint(
    ticket_id: str,
    payload: dict[str, Any],
    user: dict[str, Any] = Depends(get_current_user),
) -> Any:
    return service.add_ticket_message(
        str(user.get("sub") or "anonymous"),
        ticket_id,
        payload,
    )


@router.patch("/tickets/{ticket_id}/status")
async def update_ticket_status_endpoint(
    ticket_id: str,
    payload: dict[str, Any],
    user: dict[str, Any] = Depends(get_current_user),
) -> Any:
    return service.update_ticket_status(
        str(user.get("sub") or "anonymous"),
        ticket_id,
        payload,
    )
