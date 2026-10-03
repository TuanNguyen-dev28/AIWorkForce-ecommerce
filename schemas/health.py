from typing import Literal

from pydantic import BaseModel, ConfigDict


class HealthResult(BaseModel):
    model_config = ConfigDict(frozen=True)
    component: Literal["api", "database", "llm"]
    status: Literal["ok", "unavailable", "not_configured"]
    mode: Literal["runtime", "mysql", "mock", "disabled"]
    error_code: str | None = None


class ReadinessResult(BaseModel):
    status: Literal["ready", "not_ready"]
    components: list[HealthResult]
