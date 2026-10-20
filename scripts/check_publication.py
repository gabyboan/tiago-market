#!/usr/bin/env python3
"""Check tracked files and new candidates against publication boundaries."""

from pathlib import Path
import subprocess
import sys


def main():
    root = Path(__file__).resolve().parents[1]
    candidates = subprocess.check_output(
        ["git", "ls-files", "--cached", "--others", "--exclude-standard", "-z"],
        cwd=root,
    )
    paths = sorted(set(filter(None, candidates.split(b"\0"))))
    ignored = subprocess.run(
        ["git", "check-ignore", "--no-index", "--stdin", "-z"],
        input=b"\0".join(paths) + b"\0",
        stdout=subprocess.PIPE,
        cwd=root,
        check=False,
    )
    if ignored.returncode not in (0, 1):
        return ignored.returncode
    errors = [
        f"Private/ignored file is still tracked: {p.decode('utf-8', 'replace')}"
        for p in ignored.stdout.split(b"\0") if p
    ]
    limit = 10 * 1024 * 1024
    total = 0
    for raw in paths:
        path = root / raw.decode("utf-8", "surrogateescape")
        if path.is_symlink():
            errors.append(f"Review symlink before publishing: {path.relative_to(root)}")
        elif path.is_file():
            size = path.stat().st_size
            total += size
            if size > limit:
                errors.append(f"File exceeds 10 MiB: {path.relative_to(root)}")
    if errors:
        print("\n".join(errors), file=sys.stderr)
        return 1
    print(f"Publication boundaries OK: {len(paths)} files, {total / 1024 / 1024:.1f} MiB.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
