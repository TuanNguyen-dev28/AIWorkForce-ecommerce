from dataclasses import dataclass
from typing import Protocol


@dataclass(frozen=True)
class AuditEvent:
    workflow_id: str
    tenant_id: int
    actor_id: int
    action: str
    outcome: str


class AuditSink(Protocol):
    def append(self, event: AuditEvent) -> None: ...
