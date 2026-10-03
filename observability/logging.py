import json
import logging
from contextvars import ContextVar
from datetime import UTC, datetime

correlation_id: ContextVar[str | None] = ContextVar("correlation_id", default=None)
workflow_id: ContextVar[str | None] = ContextVar("workflow_id", default=None)

# Logs contain fixed event names and allowlisted scalar metadata only. Arbitrary
# messages, headers, exception text, request/response bodies and URLs are omitted.
SAFE_FIELDS = {"status", "error_code", "duration_ms", "component", "method", "status_code"}


class JsonFormatter(logging.Formatter):
    def format(self, record: logging.LogRecord) -> str:
        payload: dict[str, object] = {
            "timestamp": datetime.now(UTC).isoformat(),
            "level": record.levelname,
            "event": getattr(record, "event_name", "application_event"),
            "correlation_id": correlation_id.get(),
            "workflow_id": workflow_id.get(),
        }
        for key in SAFE_FIELDS:
            value = getattr(record, key, None)
            if value is not None:
                payload[key] = value
        return json.dumps(payload, ensure_ascii=False)


def configure_logging(level: str) -> None:
    handler = logging.StreamHandler()
    handler.setFormatter(JsonFormatter())
    logger = logging.getLogger("aiworkforce")
    logger.handlers = [handler]
    logger.setLevel(level)
    logger.propagate = False
    # Uvicorn otherwise formats uncaught exception text (which may contain
    # credentials). Keep its error records in the same metadata-only format.
    for name in ("uvicorn.error", "uvicorn.access"):
        server_logger = logging.getLogger(name)
        server_logger.handlers = [handler]
        server_logger.propagate = False


def log_event(event: str, **fields: str | int | float | None) -> None:
    if any(key not in SAFE_FIELDS for key in fields):
        raise ValueError("Log field is not allowlisted")
    logging.getLogger("aiworkforce").info("", extra={"event_name": event, **fields})
