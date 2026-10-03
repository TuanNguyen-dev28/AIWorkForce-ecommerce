"""Scan tracked and non-ignored files. Never print detected secret values."""

import json
import subprocess
import sys


def main() -> None:
    paths = (
        subprocess.run(
            ["git", "ls-files", "--cached", "--others", "--exclude-standard", "-z"],
            capture_output=True,
            check=True,
        )
        .stdout.decode("utf-8")
        .split("\0")
    )
    files = sorted({path for path in paths if path})
    result = subprocess.run(
        [
            sys.executable,
            "-X",
            "utf8",
            "-m",
            "detect_secrets",
            "scan",
            "--no-verify",
            "--exclude-files",
            r"(^|/)uv\.lock$",
            "--",
            *files,
        ],
        capture_output=True,
        text=True,
        encoding="utf-8",
        check=False,
    )
    if result.returncode:
        raise SystemExit("Secret scanner could not run; check installation and process permissions")
    findings = json.loads(result.stdout)["results"]
    if findings:
        for path, hits in findings.items():
            for hit in hits:
                print(f"Potential secret: {path}:{hit['line_number']} ({hit['type']})")
        sys.exit(1)
    print(f"Secret scan passed ({len(files)} repository files; no findings).")


if __name__ == "__main__":
    main()
