import logging
import uuid

from fastapi import FastAPI, Request
from fastapi.exceptions import RequestValidationError
from fastapi.responses import JSONResponse
from starlette.exceptions import HTTPException as StarletteHTTPException

logger = logging.getLogger("pharmacy.api")

_STATUS_CODES = {
    400: "BAD_REQUEST",
    401: "UNAUTHENTICATED",
    403: "FORBIDDEN",
    404: "NOT_FOUND",
    405: "METHOD_NOT_ALLOWED",
    409: "CONFLICT",
    422: "VALIDATION_ERROR",
    429: "RATE_LIMITED",
    503: "SERVICE_UNAVAILABLE",
}


class ApiError(Exception):
    """Raised by services to return the shared error envelope."""

    def __init__(
        self,
        status_code: int,
        code: str,
        message: str,
        field_errors: dict[str, str] | None = None,
    ) -> None:
        super().__init__(message)
        self.status_code = status_code
        self.code = code
        self.message = message
        self.field_errors = field_errors


def default_code(status_code: int) -> str:
    return _STATUS_CODES.get(status_code, "INTERNAL_ERROR")


def error_response(
    status_code: int,
    code: str,
    message: str,
    field_errors: dict[str, str] | None = None,
) -> JSONResponse:
    return JSONResponse(
        status_code=status_code,
        content={
            "statusCode": status_code,
            "code": code,
            "message": message,
            "fieldErrors": field_errors,
            "requestId": str(uuid.uuid4()),
        },
    )


def install_error_handlers(app: FastAPI) -> None:
    @app.exception_handler(ApiError)
    async def _api_error(_request: Request, exc: ApiError) -> JSONResponse:
        return error_response(exc.status_code, exc.code, exc.message, exc.field_errors)

    @app.exception_handler(RequestValidationError)
    async def _validation_error(_request: Request, exc: RequestValidationError) -> JSONResponse:
        field_errors: dict[str, str] = {}
        for error in exc.errors():
            location = [str(part) for part in error.get("loc", ()) if part not in ("body", "query", "path")]
            field = location[-1] if location else "field"
            field_errors[field] = str(error.get("msg", "Invalid value"))
        return error_response(400, "VALIDATION_ERROR", "Validation failed", field_errors)

    @app.exception_handler(StarletteHTTPException)
    async def _http_error(_request: Request, exc: StarletteHTTPException) -> JSONResponse:
        detail = exc.detail
        if isinstance(detail, dict) and "code" in detail:
            return error_response(
                exc.status_code,
                str(detail.get("code")),
                str(detail.get("message", "Request failed")),
            )
        message = detail if isinstance(detail, str) else "Request failed"
        return error_response(exc.status_code, default_code(exc.status_code), message)

    @app.exception_handler(Exception)
    async def _unhandled(_request: Request, exc: Exception) -> JSONResponse:
        logger.exception("Unhandled error", exc_info=exc)
        return error_response(500, "INTERNAL_ERROR", "Something went wrong")
