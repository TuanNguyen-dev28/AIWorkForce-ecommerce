import json
import secrets
import subprocess
import sys
from pathlib import Path

import pytest

pytestmark = pytest.mark.security


def test_scanner_detects_synthetic_credentials(tmp_path: Path) -> None:
    sample = tmp_path / "synthetic_secret.py"
    # Random test-only data has no account/provider; do not use a real credential.
    sample.write_text("api_" + "key = '" + secrets.token_urlsafe(32) + "'\n", encoding="utf-8")
    output = subprocess.run(
        [
            sys.executable,
            "-X",
            "utf8",
            "-m",
            "detect_secrets",
            "scan",
            "--no-verify",
            "--",
            sample.name,
        ],
        capture_output=True,
        text=True,
        encoding="utf-8",
        check=False,
        cwd=tmp_path,
    )
    assert output.returncode == 0, "Scanner subprocess must complete successfully"
    assert json.loads(output.stdout)["results"], "Secret detector must flag a generated fixture"
