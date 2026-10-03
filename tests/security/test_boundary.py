import io
import json
import logging
from dataclasses import replace
from unittest.mock import patch

import pytest
from fastapi.testclient import TestClient

from api.main import create_app
from audit.contracts import AuditEvent
from config.settings import Settings
from fixtures.harness import FakeAuditSink, FakeAuthorizer, FakeIdempotencyStore, FakePolicy
from observability.logging import JsonFormatter
from security.contracts import TrustedContext

pytestmark = pytest.mark.security


def test_authorization_allow_and_deny(
    authorizer: FakeAuthorizer, trusted_context: TrustedContext
) -> None:
    authorizer.require(trusted_context, "inventory.read")
    with pytest.raises(PermissionError):
        authorizer.require(trusted_context, "inventory.write")


def test_policy_allow_and_deny(policy: FakePolicy, trusted_context: TrustedContext) -> None:
    policy.require(trusted_context, "inventory.read")
    with pytest.raises(PermissionError):
        policy.require(trusted_context, "inventory.write")


def test_idempotency_replay_conflict_and_tenant_scope(
    idempotency_store: FakeIdempotencyStore,
    trusted_context: TrustedContext,
) -> None:
    assert idempotency_store.reserve(trusted_context, "key-1", "hash-1")
    assert not idempotency_store.reserve(trusted_context, "key-1", "hash-1")
    with pytest.raises(ValueError):
        idempotency_store.reserve(trusted_context, "key-1", "hash-2")
    assert idempotency_store.reserve(replace(trusted_context, tenant_id=2), "key-1", "hash-2")


def test_audit_fixture_preserves_workflow(
    audit_sink: FakeAuditSink, trusted_context: TrustedContext
) -> None:
    event = AuditEvent(trusted_context.workflow_id, 1, 10, "inventory.read", "allowed")
    audit_sink.append(event)
    assert audit_sink.events == [event]


def test_correlation_id_is_validated_and_context_does_not_leak(client: TestClient) -> None:
    first = client.get("/health/live", headers={"X-Correlation-ID": "trace-one"})
    assert first.headers["x-correlation-id"] == "trace-one"
    second = client.get("/health/live", headers={"X-Correlation-ID": "bad id with spaces"})
    assert second.headers["x-correlation-id"] != "bad id with spaces"
    assert len(second.headers["x-correlation-id"]) == 32
    assert client.get("/health/live").headers["x-correlation-id"] != "trace-one"


def test_driver_errors_do_not_expose_secrets(
    settings: Settings, capsys: pytest.CaptureFixture[str]
) -> None:
    active = settings.model_copy(update={"database_enabled": True})
    with (
        patch("api.health.connect", side_effect=RuntimeError("credential-fixture / private-user")),
        TestClient(create_app(active)) as client,
    ):
        response = client.get("/health/database")
    assert response.status_code == 503
    text = response.text + capsys.readouterr().err
    assert "credential-fixture" not in text
    assert "private-user" not in text


def test_headers_and_pii_are_not_logged(client: TestClient) -> None:
    buffer = io.StringIO()
    handler = logging.StreamHandler(buffer)
    handler.setFormatter(JsonFormatter())
    logger = logging.getLogger("aiworkforce")
    logger.addHandler(handler)
    try:
        client.get(
            "/health/live?email=private@example.invalid",
            headers={
                "Authorization": "Bearer sensitive-fixture",
                "X-Workflow-ID": "untrusted-workflow",
            },
        )
        output = buffer.getvalue()
    finally:
        logger.removeHandler(handler)
    assert "private@example.invalid" not in output
    assert "sensitive-fixture" not in output
    assert "untrusted-workflow" not in output
    entries = [json.loads(line) for line in output.splitlines() if line.startswith("{")]
    assert any(entry["event"] == "http_request" for entry in entries)
    assert all(entry["workflow_id"] is None for entry in entries)


def test_no_business_write_endpoints(client: TestClient) -> None:
    assert client.post("/inventory", json={"quantity": 1}).status_code == 404


def test_unexpected_error_keeps_trace_and_redacts_exception(settings: Settings) -> None:
    app = create_app(settings)

    @app.get("/test-only-failure")
    def fail() -> None:
        raise RuntimeError("private-driver-fixture")

    with TestClient(app, raise_server_exceptions=False) as client:
        buffer = io.StringIO()
        handler = logging.StreamHandler(buffer)
        handler.setFormatter(JsonFormatter())
        logger = logging.getLogger("aiworkforce")
        logger.addHandler(handler)
        try:
            response = client.get("/test-only-failure")
        finally:
            logger.removeHandler(handler)
    assert response.status_code == 500
    assert response.json() == {"error_code": "INTERNAL_ERROR"}
    entries = [json.loads(line) for line in buffer.getvalue().splitlines()]
    assert entries[0]["correlation_id"] == response.headers["x-correlation-id"]
    assert "private-driver-fixture" not in response.text + buffer.getvalue()


def test_configuration_errors_do_not_expose_environment_values(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    from config.settings import load_settings

    monkeypatch.setenv("APP_ENV", "production")
    monkeypatch.setenv("DATABASE_PASSWORD", "configuration-fixture-private")
    monkeypatch.setenv("DATABASE_ENABLED", "false")
    with pytest.raises(RuntimeError) as error:
        load_settings()
    assert "configuration-fixture-private" not in str(error.value)
