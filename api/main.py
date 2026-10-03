import re
import time
from collections.abc import AsyncIterator
from contextlib import asynccontextmanager
from uuid import uuid4

from fastapi import FastAPI, Request
from fastapi.responses import JSONResponse
from starlette.concurrency import run_in_threadpool
from starlette.types import ASGIApp, Message, Receive, Scope, Send

from api.health import check_database
from config.settings import Settings, load_settings
from llm.health import check_llm
from observability.logging import configure_logging, correlation_id, log_event, workflow_id
from schemas.health import HealthResult, ReadinessResult


def safe_id(value: str | None) -> str:
    return value if value and re.fullmatch(r"[A-Za-z0-9_-]{1,64}", value) else uuid4().hex


class CorrelationMiddleware:
    def __init__(self, app: ASGIApp) -> None:
        self.app = app

    async def __call__(self, scope: Scope, receive: Receive, send: Send) -> None:
        if scope["type"] != "http":
            await self.app(scope, receive, send)
            return
        request = Request(scope)
        cid = safe_id(request.headers.get("x-correlation-id"))
        request.state.correlation_id = cid
        cid_token = correlation_id.set(cid)
        # A health request has no trusted business workflow. Never accept a
        # client-provided workflow ID as workflow identity.
        wid_token = workflow_id.set(None)
        started = time.monotonic()
        status_code = 500

        async def traced_send(message: Message) -> None:
            nonlocal status_code
            if message["type"] == "http.response.start":
                status_code = message["status"]
                headers = list(message.get("headers", []))
                headers.append((b"x-correlation-id", cid.encode("ascii")))
                message["headers"] = headers
            await send(message)

        try:
            await self.app(scope, receive, traced_send)
        finally:
            log_event(
                "http_request",
                method=scope["method"],
                status_code=status_code,
                duration_ms=round((time.monotonic() - started) * 1000, 2),
            )
            workflow_id.reset(wid_token)
            correlation_id.reset(cid_token)


def create_app(settings: Settings | None = None) -> FastAPI:
    active = settings or load_settings()

    @asynccontextmanager
    async def lifespan(_: FastAPI) -> AsyncIterator[None]:
        configure_logging(active.log_level)
        log_event("api_started", status=active.app_env)
        yield
        log_event("api_stopped", status="ok")

    app = FastAPI(
        title="AI Workforce",
        version="0.1.0",
        lifespan=lifespan,
        docs_url="/docs" if active.app_env in {"dev", "test"} else None,
        redoc_url=None,
        openapi_url="/openapi.json" if active.app_env in {"dev", "test"} else None,
    )
    app.add_middleware(CorrelationMiddleware)

    @app.exception_handler(Exception)
    async def unexpected_error(request: Request, _: Exception) -> JSONResponse:
        # ServerErrorMiddleware calls this outside the correlation middleware.
        return JSONResponse(
            status_code=500,
            content={"error_code": "INTERNAL_ERROR"},
            headers={"X-Correlation-ID": request.state.correlation_id},
        )

    @app.get("/health/live", response_model=HealthResult)
    def live() -> HealthResult:
        return HealthResult(component="api", status="ok", mode="runtime")

    @app.get("/health/database", response_model=HealthResult)
    def database() -> JSONResponse:
        result = check_database(active)
        return JSONResponse(result.model_dump(), status_code=200 if result.status == "ok" else 503)

    @app.get("/health/llm", response_model=HealthResult)
    def llm() -> JSONResponse:
        result = check_llm(active)
        return JSONResponse(result.model_dump(), status_code=200 if result.status == "ok" else 503)

    @app.get("/health/ready", response_model=ReadinessResult)
    async def ready() -> JSONResponse:
        db = await run_in_threadpool(check_database, active)
        provider = check_llm(active)
        ok = db.status == "ok" and provider.status == "ok"
        result = ReadinessResult(status="ready" if ok else "not_ready", components=[db, provider])
        return JSONResponse(result.model_dump(), status_code=200 if ok else 503)

    # Config is fixed per application instance; probes never mutate persistence.
    app.state.settings = active
    return app


def factory() -> FastAPI:
    return create_app()
