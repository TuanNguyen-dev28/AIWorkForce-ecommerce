import pytest
from pydantic import SecretStr, ValidationError

from config.settings import Settings


@pytest.mark.parametrize("environment", ["staging", "production"])
def test_deployed_environments_require_credentials(environment: str) -> None:
    with pytest.raises(ValidationError):
        Settings(_env_file=None, app_env=environment)  # type: ignore[call-arg,arg-type]


@pytest.mark.parametrize("user,provider", [("root", "disabled"), ("runtime", "mock")])
def test_deployed_environments_reject_root_and_mock(user: str, provider: str) -> None:
    with pytest.raises(ValidationError):
        Settings(  # type: ignore[call-arg]
            _env_file=None,
            app_env="production",
            database_enabled=True,
            database_user=user,
            database_password=SecretStr("synthetic-fixture-value"),
            llm_provider=provider,  # type: ignore[arg-type]
        )


def test_environment_file_precedence(tmp_path: object, monkeypatch: pytest.MonkeyPatch) -> None:
    from pathlib import Path

    from config.settings import load_settings

    assert isinstance(tmp_path, Path)
    template = tmp_path / "dev.env"
    template.write_text("APP_ENV=test\nLOG_LEVEL=DEBUG\n", encoding="utf-8")
    monkeypatch.setenv("ENV_FILE", str(template))
    monkeypatch.setenv("LOG_LEVEL", "WARNING")
    assert load_settings().log_level == "WARNING"
