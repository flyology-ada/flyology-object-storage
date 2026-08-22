#!/usr/bin/env python3
"""Reject broken repository-local links in tracked Markdown files."""

from __future__ import annotations

import pathlib
import re
import subprocess
import sys
import urllib.parse


PROJECT_DIR = pathlib.Path(__file__).resolve().parents[2]
LINK = re.compile(r"!?\[[^\]]*\]\(([^)]+)\)")


def tracked_markdown() -> list[pathlib.Path]:
    result = subprocess.run(
        ["git", "ls-files", "-z", "--", "*.md"],
        cwd=PROJECT_DIR,
        check=True,
        stdout=subprocess.PIPE,
    )
    return [
        PROJECT_DIR / pathlib.Path(item.decode("utf-8"))
        for item in result.stdout.split(b"\0")
        if item
    ]


def local_target(raw_target: str) -> str | None:
    target = raw_target.strip()
    if target.startswith("<") and target.endswith(">"):
        target = target[1:-1]
    if not target or target.startswith("#"):
        return None
    parsed = urllib.parse.urlsplit(target)
    if parsed.scheme or parsed.netloc:
        return None
    return urllib.parse.unquote(parsed.path)


def is_ignored(destination: pathlib.Path) -> bool:
    try:
        relative = destination.resolve().relative_to(PROJECT_DIR)
    except ValueError:
        return False
    return subprocess.run(
        ["git", "check-ignore", "--quiet", "--", str(relative)],
        cwd=PROJECT_DIR,
        check=False,
    ).returncode == 0


def main() -> int:
    failures: list[str] = []
    files = tracked_markdown()
    for source in files:
        text = source.read_text(encoding="utf-8")
        for match in LINK.finditer(text):
            target = local_target(match.group(1))
            if target is None:
                continue
            destination = (
                PROJECT_DIR / target.lstrip("/")
                if target.startswith("/")
                else source.parent / target
            )
            if not destination.exists() and not is_ignored(destination):
                line = text.count("\n", 0, match.start()) + 1
                failures.append(
                    f"{source.relative_to(PROJECT_DIR)}:{line}: "
                    f"missing local link target {target}"
                )

    if failures:
        print("\n".join(failures), file=sys.stderr)
        return 1
    print(f"Markdown links: {len(files)} tracked files OK")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
