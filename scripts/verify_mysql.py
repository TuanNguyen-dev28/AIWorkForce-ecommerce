"""Run migration integration tests on a NEW hidden local MySQL process, then stop it.

Windows: uses installed MySQL binaries, random loopback port, disposable data under
.local. Does not connect to, stop, or alter the existing MySQL80 service.
"""

import argparse
import os
import socket
import subprocess
import sys
import tempfile
import time
from pathlib import Path

import pymysql

from config.settings import Settings
from database.connection import connect


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--mysql-bin", type=Path, default=Path("C:/Program Files/MySQL/MySQL Server 8.0/bin")
    )
    args = parser.parse_args()
    executable = args.mysql_bin / ("mysqld.exe" if os.name == "nt" else "mysqld")
    if not executable.is_file():
        raise SystemExit("Missing mysqld executable")
    root = Path(__file__).resolve().parents[1]
    (root / ".local").mkdir(exist_ok=True)
    target = Path(tempfile.mkdtemp(prefix="phase1-mysql-", dir=root / ".local"))
    # Both paths must resolve inside the workspace-owned .local directory.
    if not target.resolve().is_relative_to((root / ".local").resolve()):
        raise SystemExit("Unexpected temporary data directory")
    hidden = getattr(subprocess, "CREATE_NO_WINDOW", 0)
    subprocess.run(
        [
            str(executable),
            "--no-defaults",
            "--initialize-insecure",
            f"--datadir={target / 'data'}",
            "--console",
        ],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.PIPE,
        check=True,
        creationflags=hidden,
        timeout=120,
    )
    with socket.socket() as sock:
        sock.bind(("127.0.0.1", 0))
        port = sock.getsockname()[1]
    settings = Settings(  # type: ignore[call-arg]
        _env_file=None,
        app_env="test",
        database_enabled=True,
        database_user="root",
        database_port=port,
        dependency_timeout_seconds=1,
    )
    server = subprocess.Popen(
        [
            str(executable),
            "--no-defaults",
            f"--datadir={target / 'data'}",
            f"--port={port}",
            "--bind-address=127.0.0.1",
            "--mysqlx=OFF",
            "--skip-log-bin",
            "--innodb-buffer-pool-size=64M",
            f"--log-error={target / 'server.err'}",
            f"--pid-file={target / 'server.pid'}",
        ],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        creationflags=hidden,
    )
    try:
        for _ in range(60):
            if server.poll() is not None:
                raise RuntimeError(f"Disposable MySQL exited; see {target / 'server.err'}")
            try:
                connection = connect(settings, select_database=False)
                connection.close()
                break
            except pymysql.MySQLError:
                time.sleep(0.5)
        else:
            raise RuntimeError("Timed out waiting for disposable MySQL")
        environment = dict(os.environ)
        environment.update(
            TEST_MYSQL="1",
            TEST_MYSQL_HOST="127.0.0.1",
            TEST_MYSQL_PORT=str(port),
            TEST_MYSQL_PASSWORD="",
        )
        result = subprocess.run(
            [sys.executable, "-m", "pytest", "tests/integration", "-q"],
            env=environment,
            cwd=root,
            creationflags=hidden,
            check=False,
            capture_output=True,
            text=True,
            encoding="utf-8",
        )
        print(result.stdout)
        if result.stderr:
            print(result.stderr, file=sys.stderr)
        raise SystemExit(result.returncode)
    finally:
        server.terminate()
        try:
            server.wait(timeout=15)
        except subprocess.TimeoutExpired:
            server.kill()
            server.wait(timeout=5)
        print(f"Disposable MySQL stopped. Logs retained in {target}")


if __name__ == "__main__":
    main()
