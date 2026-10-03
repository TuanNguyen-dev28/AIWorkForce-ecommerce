from unittest.mock import MagicMock, patch

from fastapi.testclient import TestClient

from api.main import create_app
from config.settings import Settings


def test_liveness_and_mock_provider(client: TestClient) -> None:
    assert client.get("/health/live").json()["status"] == "ok"
    result = client.get("/health/llm")
    assert result.status_code == 200
    assert result.json()["mode"] == "mock"


def test_disabled_database_is_not_ready(client: TestClient) -> None:
    assert client.get("/health/database").status_code == 503
    result = client.get("/health/ready")
    assert result.status_code == 503
    assert result.json()["status"] == "not_ready"


def test_live_does_not_probe_dependencies(client: TestClient) -> None:
    with patch("api.health.connect") as connector:
        assert client.get("/health/live").status_code == 200
        connector.assert_not_called()


def test_database_ready_and_connection_closed(settings: Settings) -> None:
    connection = MagicMock()
    connection.cursor.return_value.__enter__.return_value.fetchone.return_value = (1,)
    with (
        patch("api.health.connect", return_value=connection),
        TestClient(create_app(settings.model_copy(update={"database_enabled": True}))) as client,
    ):
        assert client.get("/health/ready").status_code == 200
    connection.close.assert_called_once()


def test_provider_disabled_is_not_ready(settings: Settings) -> None:
    with TestClient(create_app(settings.model_copy(update={"llm_provider": "disabled"}))) as client:
        assert client.get("/health/llm").status_code == 503
