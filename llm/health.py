from config.settings import Settings
from schemas.health import HealthResult


def check_llm(settings: Settings) -> HealthResult:
    if settings.llm_provider == "mock":
        return HealthResult(component="llm", status="ok", mode="mock")
    return HealthResult(
        component="llm", status="not_configured", mode="disabled", error_code="LLM_NOT_CONFIGURED"
    )
