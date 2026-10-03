import os
from pathlib import Path
from shutil import copytree

import pytest
from pydantic import SecretStr

from api.health import check_database
from config.settings import Settings
from database.connection import connect
from database.migrate import MigrationError, apply, discover, pending

pytestmark = [
    pytest.mark.integration,
    pytest.mark.skipif(
        os.environ.get("TEST_MYSQL") != "1", reason="Set TEST_MYSQL=1 for isolated MySQL"
    ),
]


def test_fresh_apply_replay_checksums_and_partial_failure(tmp_path: Path) -> None:
    # CI service / scripts.verify_mysql supplies an explicitly disposable server.
    settings = Settings(  # type: ignore[call-arg]
        _env_file=None,
        app_env="test",
        database_enabled=True,
        database_host=os.environ.get("TEST_MYSQL_HOST", "127.0.0.1"),
        database_port=int(os.environ.get("TEST_MYSQL_PORT", "3306")),
        database_user="root",
        database_password=SecretStr(os.environ.get("TEST_MYSQL_PASSWORD", "")),
        dependency_timeout_seconds=10,
    )
    connection = connect(settings, select_database=False)
    try:
        with connection.cursor() as cursor:
            cursor.execute("SHOW DATABASES LIKE 'aiworkforce_ecommerce'")
            assert cursor.fetchone() is None, (
                "Integration suite requires a fresh disposable database"
            )
    finally:
        connection.close()
    assert apply(settings) == ["001", "002"]
    assert apply(settings) == []
    assert check_database(settings).status == "ok"
    connection = connect(settings)
    try:
        assert pending(connection, discover()) == []
        with connection.cursor() as cursor:
            cursor.execute("SHOW TRIGGERS")
            assert len(cursor.fetchall()) == 7
    finally:
        connection.close()
    source = Path(__file__).resolve().parents[2] / "database/mysql"
    target = tmp_path / "sql"
    copytree(source.resolve(), target)
    first = target / "migrations/001_initial_schema.sql"
    first.write_text(first.read_text(encoding="utf-8") + "\n-- changed\n", encoding="utf-8")
    with pytest.raises(MigrationError, match="Checksum mismatch"):
        apply(settings, target)
    first.write_bytes((source / "migrations/001_initial_schema.sql").read_bytes())
    broken = target / "migrations/003_failure.sql"
    broken.write_text(
        "CREATE TABLE partial_ddl (id INT); SELECT * FROM missing_table;", encoding="utf-8"
    )
    with pytest.raises(MigrationError, match="manual recovery"):
        apply(settings, target)
    with pytest.raises(MigrationError, match="manual recovery"):
        apply(settings, target)
