"""Synthetic test doubles. No persistence, authentication or production guarantees."""

from dataclasses import replace

from audit.contracts import AuditEvent
from security.contracts import TrustedContext


class FakeAuthorizer:
    def require(self, context: TrustedContext, permission: str) -> None:
        if permission not in context.permissions:
            raise PermissionError("Permission denied")


class FakePolicy:
    def require(self, context: TrustedContext, action: str) -> None:
        if context.tenant_id <= 0 or action != "inventory.read":
            raise PermissionError("Policy denied")


class FakeIdempotencyStore:
    def __init__(self) -> None:
        self.records: dict[tuple[int, str], str] = {}

    def reserve(self, context: TrustedContext, key: str, payload_hash: str) -> bool:
        scoped = (context.tenant_id, key)
        if scoped in self.records:
            if self.records[scoped] != payload_hash:
                raise ValueError("Idempotency conflict")
            return False
        self.records[scoped] = payload_hash
        return True


class FakeAuditSink:
    def __init__(self) -> None:
        self.events: list[AuditEvent] = []

    def append(self, event: AuditEvent) -> None:
        self.events.append(replace(event))
