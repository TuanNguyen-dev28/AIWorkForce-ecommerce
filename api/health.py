from config.settings import Settings
from database.connection import connect
from observability.logging import log_event
from schemas.health import HealthResult


def check_database(settings: Settings) -> HealthResult:
    if not settings.database_enabled:
        return HealthResult(
            component="database", status="not_configured", mode="mysql", error_code="DB_DISABLED"
        )
    try:
        connection = connect(settings)
        try:
            with connection.cursor() as cursor:
                cursor.execute("SELECT 1")
                if cursor.fetchone() != (1,):
                    raise RuntimeError("Unexpected database health result")
        finally:
            connection.close()
    except Exception:
        # Do not publish connection strings, credential-bearing errors or driver text.
        log_event(
            "dependency_health",
            component="database",
            status="unavailable",
            error_code="DB_UNAVAILABLE",
        )
        return HealthResult(
            component="database", status="unavailable", mode="mysql", error_code="DB_UNAVAILABLE"
        )
    return HealthResult(component="database", status="ok", mode="mysql")
