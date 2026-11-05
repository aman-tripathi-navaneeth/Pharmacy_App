"""Stable error shape required by docs/api-conventions.md: {"detail": "...", "code": "..."}.

The custom route class below turns ApiError into that shape without touching the shared
app/main.py. If the team later adds one app-wide handler, this class can be removed.
"""

from fastapi import Request, Response
from fastapi.responses import JSONResponse
from fastapi.routing import APIRoute


class ApiError(Exception):
    def __init__(self, status_code: int, code: str, detail: str) -> None:
        super().__init__(detail)
        self.status_code = status_code
        self.code = code
        self.detail = detail


class ApiErrorRoute(APIRoute):
    def get_route_handler(self):
        original = super().get_route_handler()

        async def handler(request: Request) -> Response:
            try:
                return await original(request)
            except ApiError as exc:
                return JSONResponse(
                    status_code=exc.status_code,
                    content={"detail": exc.detail, "code": exc.code},
                )

        return handler
