import json
import logging
from decimal import Decimal

import pytest

from observability.cost import CostEvent, InMemoryCostAccounting
from observability.logging import JsonFormatter, correlation_id, log_event, workflow_id


def test_log_contains_correlation_and_workflow_without_exception_text() -> None:
    cid = correlation_id.set("trace-1")
    wid = workflow_id.set("workflow-1")
    try:
        record = logging.LogRecord("aiworkforce", logging.INFO, "", 0, "private text", (), None)
        record.authorization = "sensitive-fixture"
        payload = json.loads(JsonFormatter().format(record))
        assert payload["correlation_id"] == "trace-1"
        assert payload["workflow_id"] == "workflow-1"
        assert "private text" not in json.dumps(payload)
        assert "sensitive-fixture" not in json.dumps(payload)
    finally:
        workflow_id.reset(wid)
        correlation_id.reset(cid)


def test_log_rejects_unknown_fields() -> None:
    with pytest.raises(ValueError):
        # Synthetic value checks the allowlist; it is not a credential.
        log_event("event", password="synthetic-fixture")  # pragma: allowlist secret


def test_cost_totals_keep_workflows_and_currencies_separate() -> None:
    costs = InMemoryCostAccounting()
    costs.record(CostEvent("wf-1", "mock", "mock", 10, 5, Decimal("0.01")))
    costs.record(CostEvent("wf-2", "mock", "mock", 2, 1, Decimal("0.02")))
    costs.record(CostEvent("wf-1", "mock", "mock", 2, 1, Decimal("1"), "VND"))
    assert costs.total("wf-1") == Decimal("0.01")
    assert costs.total("wf-2") == Decimal("0.02")
    assert costs.total("wf-1", "VND") == Decimal("1")


@pytest.mark.parametrize("amount", [Decimal("-1"), Decimal("NaN"), Decimal("Infinity")])
def test_cost_rejects_invalid_amounts(amount: Decimal) -> None:
    with pytest.raises(ValueError):
        CostEvent("wf-1", "mock", "mock", 1, 1, amount)
