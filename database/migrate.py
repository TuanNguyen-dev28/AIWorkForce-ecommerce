"""Versioned MySQL SQL runner. Never retries partially committed DDL automatically."""

import argparse
import hashlib
import re
from contextlib import suppress
from dataclasses import dataclass
from pathlib import Path
from uuid import uuid4

import pymysql
from pymysql.connections import Connection

from config.settings import Settings, load_settings
from database.connection import connect
from database.sql import split_sql
from observability.logging import configure_logging, correlation_id, log_event, workflow_id

SQL_ROOT = Path(__file__).resolve().parent / "mysql"
LOCK_NAME = "aiworkforce_ecommerce:migrations"


class MigrationError(RuntimeError):
    """Safe operator error; contains no driver output or credentials."""


@dataclass(frozen=True)
class Migration:
    version: str
    checksum: str
    statements: list[str]


def discover(root: Path = SQL_ROOT) -> list[Migration]:
    migrations = []
    seen: set[str] = set()
    for path in sorted((root / "migrations").glob("*.sql")):
        match = re.fullmatch(r"(\d{3})_[A-Za-z0-9_]+\.sql", path.name)
        if not match or match[1] in seen:
            raise MigrationError("Invalid or duplicate migration version")
        seen.add(match[1])
        source = path.read_text(encoding="utf-8-sig")
        raw = source.encode("utf-8")
        migrations.append(Migration(match[1], hashlib.sha256(raw).hexdigest(), split_sql(source)))
    if not migrations:
        raise MigrationError("No migrations found")
    return migrations


def fetch_history(connection: Connection) -> dict[str, tuple[str, str]]:
    with connection.cursor() as cursor:
        try:
            cursor.execute("SELECT version, checksum, status FROM _migration_runs")
            return {str(row[0]): (str(row[1]), str(row[2])) for row in cursor.fetchall()}
        except pymysql.err.ProgrammingError as error:
            if error.args[0] != 1146:
                raise
            return {}


def legacy_versions(connection: Connection) -> set[str]:
    with connection.cursor() as cursor:
        try:
            cursor.execute("SELECT version FROM schema_migrations")
            return {str(row[0]) for row in cursor.fetchall()}
        except pymysql.err.ProgrammingError as error:
            if error.args[0] != 1146:
                raise
            return set()


def pending(connection: Connection, migrations: list[Migration]) -> list[Migration]:
    history = fetch_history(connection)
    legacy = legacy_versions(connection)
    known = {migration.version for migration in migrations}
    if (set(history) | legacy) - known:
        raise MigrationError("Database has unknown migration versions")
    for migration in migrations:
        recorded = history.get(migration.version)
        if recorded:
            checksum, status = recorded
            if checksum != migration.checksum:
                raise MigrationError(f"Checksum mismatch for migration {migration.version}")
            if status != "APPLIED":
                raise MigrationError(f"Migration {migration.version} requires manual recovery")
            if migration.version not in legacy:
                raise MigrationError(
                    f"Missing SQL version marker for migration {migration.version}"
                )
        elif migration.version in legacy:
            raise MigrationError("Legacy Workbench install has no checksums; see migration runbook")
    applied = [m.version for m in migrations if m.version in history]
    if applied != [m.version for m in migrations[: len(applied)]]:
        raise MigrationError("Applied migrations are not a contiguous prefix")
    return [m for m in migrations if m.version not in history]


def apply(settings: Settings, root: Path = SQL_ROOT) -> list[str]:
    if settings.app_env not in {"dev", "test"}:
        raise MigrationError("Phase 1 runner is restricted to dev/test")
    if not settings.database_enabled:
        raise MigrationError("Database is disabled")
    migrations = discover(root)
    connection = connect(settings, select_database=False)
    locked = False
    try:
        with connection.cursor() as cursor:
            cursor.execute("SELECT VERSION()")
            row = cursor.fetchone()
            version = str(row[0]) if row else ""
            match = re.match(r"(\d+)\.(\d+)\.(\d+)", version)
            if (
                not match
                or "mariadb" in version.lower()
                or tuple(map(int, match.groups())) < (8, 0, 16)
            ):
                raise MigrationError("MySQL 8.0.16 or newer is required")
            cursor.execute("SELECT GET_LOCK(%s, 5)", (LOCK_NAME,))
            locked = cursor.fetchone() == (1,)
            if not locked:
                raise MigrationError("Another migration runner holds the lock")
            for statement in split_sql(
                (root / "00_create_database.sql").read_text(encoding="utf-8")
            ):
                cursor.execute(statement)
            todo = pending(connection, migrations)
            cursor.execute("""
                CREATE TABLE IF NOT EXISTS _migration_runs (
                    version VARCHAR(32) CHARACTER SET ascii COLLATE ascii_bin PRIMARY KEY,
                    checksum CHAR(64) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
                    status VARCHAR(16) NOT NULL,
                    started_at TIMESTAMP(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
                    finished_at TIMESTAMP(6) NULL
                ) ENGINE=InnoDB
            """)
            for migration in todo:
                cursor.execute(
                    "INSERT INTO _migration_runs (version, checksum, status) "
                    "VALUES (%s, %s, 'STARTED')",
                    (migration.version, migration.checksum),
                )
                try:
                    for statement in migration.statements:
                        cursor.execute(statement)
                    cursor.execute(
                        "SELECT version FROM schema_migrations WHERE version=%s",
                        (migration.version,),
                    )
                    if cursor.fetchone() != (migration.version,):
                        raise MigrationError("Migration did not write its SQL version marker")
                    cursor.execute(
                        "UPDATE _migration_runs SET status='APPLIED', "
                        "finished_at=CURRENT_TIMESTAMP(6) WHERE version=%s",
                        (migration.version,),
                    )
                    log_event("migration_applied", status=migration.version)
                except Exception as error:
                    # MySQL DDL commits implicitly. A STARTED/FAILED record blocks
                    # subsequent runs even if the connection dies before this UPDATE.
                    with suppress(Exception):
                        cursor.execute(
                            "UPDATE _migration_runs SET status='FAILED' WHERE version=%s",
                            (migration.version,),
                        )
                    raise MigrationError(
                        f"Migration {migration.version} failed; manual recovery required"
                    ) from error
            return [migration.version for migration in todo]
    finally:
        if locked:
            try:
                with connection.cursor() as cursor:
                    cursor.execute("SELECT RELEASE_LOCK(%s)", (LOCK_NAME,))
            finally:
                connection.close()
        else:
            connection.close()


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("command", choices=["apply", "status"])
    args = parser.parse_args()
    cid = correlation_id.set(uuid4().hex)
    wid = workflow_id.set("migration-" + uuid4().hex)
    try:
        settings = load_settings()
        configure_logging(settings.log_level)
        if args.command == "apply":
            versions = apply(settings)
            print("Applied: " + (", ".join(versions) or "none (up to date)"))
        else:
            connection = connect(settings)
            try:
                versions = [migration.version for migration in pending(connection, discover())]
                print("Pending: " + (", ".join(versions) or "none"))
            finally:
                connection.close()
    except Exception as error:
        message = (
            str(error)
            if isinstance(error, MigrationError)
            else "Operation failed; check configuration and database access"
        )
        log_event("migration_failed", status="failed", error_code="MIGRATION_FAILED")
        raise SystemExit(message) from None
    finally:
        workflow_id.reset(wid)
        correlation_id.reset(cid)


if __name__ == "__main__":
    main()
