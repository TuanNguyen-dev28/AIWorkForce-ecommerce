import os
from typing import Literal

from pydantic import Field, SecretStr, ValidationError, model_validator
from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_file=".env", extra="ignore", frozen=True)

    app_env: Literal["dev", "test", "staging", "production"] = "dev"
    log_level: Literal["DEBUG", "INFO", "WARNING", "ERROR"] = "INFO"
    database_enabled: bool = False
    database_host: str = "127.0.0.1"
    database_port: int = Field(default=3306, ge=1, le=65535)
    database_name: Literal["aiworkforce_ecommerce"] = "aiworkforce_ecommerce"
    database_user: str = ""
    database_password: SecretStr = SecretStr("")
    dependency_timeout_seconds: int = Field(default=3, ge=1, le=30)
    llm_provider: Literal["mock", "disabled"] = "mock"

    @model_validator(mode="after")
    def validate_environment(self) -> "Settings":
        if self.database_enabled and (not self.database_user or not self.database_host):
            raise ValueError("Enabled database requires a host and user")
        if self.app_env in {"staging", "production"}:
            if not self.database_enabled or not self.database_password.get_secret_value():
                raise ValueError("Staging/production require database credentials")
            if self.database_user.lower() == "root":
                raise ValueError("Runtime must not use the root database account")
            if self.llm_provider == "mock":
                raise ValueError("Mock LLM is restricted to dev/test")
        return self


def load_settings() -> Settings:
    # ENV_FILE is an explicit operator-selected file, not user request input.
    try:
        return Settings(_env_file=os.environ.get("ENV_FILE", ".env"))  # type: ignore[call-arg]
    except ValidationError:
        # Pydantic's default traceback can include raw environment input values.
        raise RuntimeError(
            "Invalid application configuration; check environment template"
        ) from None
