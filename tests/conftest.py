from collections.abc import Iterator

import pytest
from fastapi.testclient import TestClient

from api.main import create_app
from config.settings import Settings
from fixtures.harness import FakeAuditSink, FakeAuthorizer, FakeIdempotencyStore, FakePolicy
from security.contracts import TrustedContext


@pytest.fixture
def settings() -> Settings:
    return Settings(_env_file=None, app_env="test", database_enabled=False, llm_provider="mock")  # type: ignore[call-arg]


@pytest.fixture
def client(settings: Settings) -> Iterator[TestClient]:
    with TestClient(create_app(settings)) as active:
        yield active


@pytest.fixture
def trusted_context() -> TrustedContext:
    return TrustedContext(1, 10, frozenset({"inventory.read"}), "test-workflow-1")


@pytest.fixture
def authorizer() -> FakeAuthorizer:
    return FakeAuthorizer()


@pytest.fixture
def policy() -> FakePolicy:
    return FakePolicy()


@pytest.fixture
def idempotency_store() -> FakeIdempotencyStore:
    return FakeIdempotencyStore()


@pytest.fixture
def audit_sink() -> FakeAuditSink:
    return FakeAuditSink()
