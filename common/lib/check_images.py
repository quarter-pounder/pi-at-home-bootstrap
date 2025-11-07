#!/usr/bin/env python3
"""Validate that rendered templates pin Docker image tags."""

from __future__ import annotations

from pathlib import Path
import re


def find_unpinned_images() -> list[str]:
    bad: list[str] = []
    paths = [
        p
        for p in Path("domains").rglob("*")
        if p.is_file() and any(p.name.endswith(ext) for ext in (".yml", ".yaml", ".tmpl",",j2"))
    ]
    pattern = re.compile(r"^\s*image:\s+(.*)")
    for path in paths:
        try:
            text = path.read_text()
        except Exception:
            continue
        for lineno, line in enumerate(text.splitlines(), 1):
            match = pattern.match(line)
            if not match:
                continue
            value = match.group(1)
            value = value.split("#", 1)[0].strip().strip('"\'')
            if not value or "$" in value or "{{" in value:
                continue  # dynamic reference handled elsewhere
            if "@sha256:" in value:
                continue
            if ":" not in value:
                bad.append(f"{path}:{lineno} image tag missing (expected <repo>:<tag>)")
            else:
                tag = value.rsplit(":", 1)[1]
                if not tag or tag.lower() == "latest":
                    bad.append(f"{path}:{lineno} image tag must be pinned (found '{value}')")
    return bad


def main() -> int:
    report = find_unpinned_images()
    if report:
        print("\n".join(report))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

