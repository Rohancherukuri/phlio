"""
Central exception -> HTTP response translation.

Registered once in `app/main.py`. Route handlers and domain services raise
plain `AppError` subclasses (see `app/common/exceptions.py`); this is the
only place that decides what HTTP status/body a client actually sees, which
keeps that decision consistent regardless of which domain raised the error.
"""

from __future__ import annotations

import logging

from fastapi import FastAPI, Request
from fastapi.exceptions import RequestValidationError
from fastapi.responses import JSONResponse

from app.common.exceptions import AppError
from app.common.schemas import ErrorDetail, ErrorResponse

logger = logging.getLogger("phlio.errors")


def register_exception_handlers(app: FastAPI) -> None:
    @app.exception_handler(AppError)
    async def handle_app_error(request: Request, exc: AppError) -> JSONResponse:
        request_id = getattr(request.state, "request_id", None)
        if exc.http_status >= 500:
            logger.exception("Unhandled AppError", extra={"request_id": request_id})
        body = ErrorResponse(error=ErrorDetail(code=exc.code, message=exc.message))
        return JSONResponse(status_code=exc.http_status, content=body.model_dump())

    @app.exception_handler(RequestValidationError)
    async def handle_validation_error(
        request: Request, exc: RequestValidationError
    ) -> JSONResponse:
        # FastAPI's own request-schema validation errors get the same
        # envelope shape as domain errors so clients only ever parse one
        # error format.
        first = exc.errors()[0] if exc.errors() else None
        message = first["msg"] if first else "Invalid request."
        body = ErrorResponse(error=ErrorDetail(code="invalid_request", message=message))
        return JSONResponse(status_code=422, content=body.model_dump())

    @app.exception_handler(Exception)
    async def handle_unexpected_error(request: Request, exc: Exception) -> JSONResponse:
        request_id = getattr(request.state, "request_id", None)
        logger.exception("Unhandled exception", extra={"request_id": request_id})
        body = ErrorResponse(
            error=ErrorDetail(code="internal_error", message="Something went wrong on our end.")
        )
        return JSONResponse(status_code=500, content=body.model_dump())
