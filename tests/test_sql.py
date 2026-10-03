from pathlib import Path

import pytest

from database.migrate import discover
from database.sql import split_sql


def test_current_migrations_include_complete_trigger_blocks() -> None:
    migrations = discover()
    assert [migration.version for migration in migrations] == ["001", "002"]
    triggers = [
        statement
        for statement in migrations[1].statements
        if statement.startswith("CREATE TRIGGER")
    ]
    assert len(triggers) == 7
    assert all(statement.endswith("END") for statement in triggers)


def test_delimiters_in_strings_comments_and_escaped_quotes() -> None:
    source = "-- ignored ;\nSELECT 'a; b', 'it''s', `semi;col`; /* ; */ SELECT 'escaped\\'quote';"
    assert len(split_sql(source)) == 2
    assert split_sql("SELECT 1; # comment\nSELECT 2;") == ["SELECT 1", "SELECT 2"]


@pytest.mark.parametrize("source", ["SELECT 1", "SELECT 'open;", "/* open", "/*! SELECT 1 */;"])
def test_malformed_scripts_fail_before_execution(source: str) -> None:
    with pytest.raises(ValueError):
        split_sql(source)


def test_duplicate_migration_versions_are_rejected(tmp_path: Path) -> None:
    from database.migrate import MigrationError

    directory = tmp_path / "migrations"
    directory.mkdir()
    (directory / "001_first.sql").write_text("SELECT 1;", encoding="utf-8")
    (directory / "001_second.sql").write_text("SELECT 2;", encoding="utf-8")
    with pytest.raises(MigrationError, match="duplicate"):
        discover(tmp_path)
