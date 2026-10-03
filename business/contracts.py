from typing import Protocol

from security.contracts import TrustedContext


class Policy(Protocol):
    def require(self, context: TrustedContext, action: str) -> None: ...


class IdempotencyStore(Protocol):
    def reserve(self, context: TrustedContext, key: str, payload_hash: str) -> bool: ...
