"""Validate SQL against an isolated Windows MySQL instance. Never uses MySQL80 data.

Requires existing mysql.exe/mysqld.exe (8.0.16+) and Python 3.10+; no pip packages.
The temporary instance has networking disabled and a unique shared-memory name.
Its files/logs stay under the ignored project .local directory for inspection.
"""
from __future__ import annotations

import argparse
import json
import os
from pathlib import Path
import subprocess
import tempfile
import time
import uuid

SQL_ROOT = Path(__file__).resolve().parents[1]
PROJECT_ROOT = SQL_ROOT.parents[1]
HIDDEN = getattr(subprocess, 'CREATE_NO_WINDOW', 0)


def run(args, *, sql=None, timeout=90):
    result = subprocess.run(
        [str(a) for a in args], input=sql, text=True, encoding='utf-8', errors='replace',
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=timeout, creationflags=HIDDEN,
    )
    if result.returncode:
        raise RuntimeError(f'{Path(args[0]).name} exited {result.returncode}:\n{result.stderr}\n{result.stdout}')
    return result.stdout


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--mysql-bin', type=Path, default=Path('C:/Program Files/MySQL/MySQL Server 8.0/bin'))
    parser.add_argument('--schema-only', action='store_true', help='Validate migrations before seed/tests are available.')
    opts = parser.parse_args()
    if os.name != 'nt':
        raise SystemExit('This isolated shared-memory runner targets Windows. Use the SQL scripts on other platforms.')
    mysqld, mysql = opts.mysql_bin / 'mysqld.exe', opts.mysql_bin / 'mysql.exe'
    for binary in (mysqld, mysql):
        if not binary.is_file():
            raise SystemExit(f'Missing installed executable: {binary}')
    local_root = PROJECT_ROOT / '.local'
    local_root.mkdir(exist_ok=True)
    sandbox = Path(tempfile.mkdtemp(prefix='mysql-schema-', dir=local_root))
    datadir = sandbox / 'data'
    datadir.mkdir()
    channel = 'AIWORKFORCE_CHECK_' + uuid.uuid4().hex
    client = [mysql, '--no-defaults', '--protocol=MEMORY', f'--shared-memory-base-name={channel}',
              '--user=root', '--skip-password', '--default-character-set=utf8mb4', '--batch', '--raw']
    server = None
    started = time.monotonic()
    report = {'engine': '', 'target': 'isolated shared-memory MySQL; networking disabled', 'files': [], 'passed': False}
    try:
        run([mysqld, '--no-defaults', '--initialize-insecure', f'--datadir={datadir}', '--console'], timeout=120)
        server = subprocess.Popen(
            [str(mysqld), '--no-defaults', f'--datadir={datadir}', '--shared-memory',
             f'--shared-memory-base-name={channel}', '--skip-networking', '--mysqlx=OFF',
             '--skip-log-bin', '--innodb-buffer-pool-size=64M', '--max-connections=10',
             f'--log-error={sandbox / "server.err"}', f'--pid-file={sandbox / "server.pid"}'],
            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, creationflags=HIDDEN,
        )
        for _ in range(60):
            if server.poll() is not None:
                raise RuntimeError(f'Isolated server exited {server.returncode}; see {sandbox / "server.err"}')
            try:
                report['engine'] = run(client, sql='SELECT VERSION();', timeout=3).strip()
                break
            except (RuntimeError, subprocess.TimeoutExpired):
                time.sleep(0.5)
        else:
            raise RuntimeError('Isolated server did not become ready within 30 seconds.')
        sql_files = ('bootstrap.sql',) if opts.schema_only else ('bootstrap.sql', 'seeds/001_demo.sql', 'tests/constraints.sql', 'checks/001_integrity_checks.sql')
        for relative in sql_files:
            path = SQL_ROOT / relative
            output = run(client, sql=path.read_text(encoding='utf-8-sig'))
            (sandbox / (path.stem + '.out')).write_text(output, encoding='utf-8')
            report['files'].append({'path': relative, 'status': 'PASS'})
            print(f'PASS {relative}', flush=True)
        if opts.schema_only:
            report['passed'] = True
            return
        # Check numerical fixture correctness independently of report SELECTs.
        result = run(client, sql="""
            USE aiworkforce_ecommerce;
            SELECT COUNT(*), CAST(SUM(total_amount-refunded_amount) AS DECIMAL(18,2)),
                   CAST(AVG(total_amount-refunded_amount) AS DECIMAL(18,2))
            FROM orders WHERE tenant_id=1001 AND paid_at >= '2026-09-30' AND paid_at < '2026-10-02'
              AND payment_status IN ('PAID','PARTIALLY_REFUNDED','REFUNDED') AND status <> 'CANCELLED';
            SELECT COUNT(*) FROM v_order_total_mismatches;
            SELECT COUNT(*) FROM information_schema.tables
              WHERE table_schema='aiworkforce_ecommerce' AND table_type='BASE TABLE';
        """)
        lines = result.strip().splitlines()
        if len(lines) != 6 or lines[1] != '4\t750000.00\t187500.00' or lines[3] != '0' or lines[5] != '16':
            raise RuntimeError(f'Unexpected seed/schema totals:\n{result}')
        print('PASS demo revenue/AOV, order totals and 16-table inventory', flush=True)
        report['passed'] = True
    finally:
        if server is not None and server.poll() is None:
            try:
                run(client, sql='SHUTDOWN;', timeout=10)
                server.wait(timeout=15)
            except (RuntimeError, subprocess.TimeoutExpired):
                if server.poll() is None:
                    server.terminate()
                    server.wait(timeout=10)
        report['elapsed_seconds'] = round(time.monotonic() - started, 2)
        (sandbox / 'report.json').write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding='utf-8')
        print(f'Validation logs: {sandbox}', flush=True)


if __name__ == '__main__':
    main()
