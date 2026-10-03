from decimal import Decimal

import pytest

from observability.cost import CostEvent, InMemoryCostAccounting

pytestmark = pytest.mark.evaluation


def test_mock_workflow_cost_is_measurable_without_external_model_calls() -> None:
    accounting = InMemoryCostAccounting()
    accounting.record(CostEvent("evaluation-1", "mock", "mock", 0, 0, Decimal(0)))
    assert accounting.total("evaluation-1") == 0
    assert len(accounting.events) == 1
