from dataclasses import dataclass
from typing import Protocol


@dataclass(frozen=True)
class TrustedContext:
    """Test contract only; Phase 3 must construct this from authenticated identity."""

    tenant_id: int
    actor_id: int
    permissions: frozenset[str]
    workflow_id: str


class Authorizer(Protocol):
    def require(self, context: TrustedContext, permission: str) -> None: ...
