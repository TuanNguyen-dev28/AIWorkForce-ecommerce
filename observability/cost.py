from dataclasses import dataclass
from decimal import Decimal
from typing import Protocol

from observability.logging import log_event, workflow_id


@dataclass(frozen=True)
class CostEvent:
    workflow_id: str
    provider: str
    model: str
    input_tokens: int
    output_tokens: int
    amount: Decimal
    currency: str = "USD"

    def __post_init__(self) -> None:
        if not self.workflow_id or self.input_tokens < 0 or self.output_tokens < 0:
            raise ValueError("Workflow and non-negative token counts are required")
        if not self.amount.is_finite() or self.amount < 0:
            raise ValueError("Cost must be finite and non-negative")
        if (
            len(self.currency) != 3
            or not self.currency.isascii()
            or not self.currency.isalpha()
            or not self.currency.isupper()
        ):
            raise ValueError("Currency must be a three-letter code")


class CostAccounting(Protocol):
    def record(self, event: CostEvent) -> None: ...


class InMemoryCostAccounting:
    """Development stub only: process-local, non-durable, no provider pricing assumptions."""

    def __init__(self) -> None:
        self.events: list[CostEvent] = []

    def record(self, event: CostEvent) -> None:
        self.events.append(event)
        token = workflow_id.set(event.workflow_id)
        try:
            log_event("cost_recorded", status="stub")
        finally:
            workflow_id.reset(token)

    def total(self, workflow: str, currency: str = "USD") -> Decimal:
        return sum(
            (e.amount for e in self.events if e.workflow_id == workflow and e.currency == currency),
            start=Decimal(0),
        )
