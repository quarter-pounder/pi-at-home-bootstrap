#!/usr/bin/env python3
"""Validate Terraform required_providers blocks specify versions."""

from __future__ import annotations

from pathlib import Path
import re


def main() -> int:
    tf_dir = Path("infra/terraform")
    if not tf_dir.exists():
        return 0

    missing: list[str] = []
    pattern = re.compile(r"required_providers\s*{([^}]*)}", re.DOTALL)
    provider_pattern = re.compile(r"(\w+)\s*=\s*{([^}]*)}", re.DOTALL)

    for path in tf_dir.rglob("*.tf"):
        try:
            content = path.read_text()
        except Exception:
            continue
        for block_match in pattern.finditer(content):
            body = block_match.group(1)
            for provider, conf in provider_pattern.findall(body):
                if "version" not in conf:
                    missing.append(f"{path}:{provider}")

    if missing:
        print("\n".join(missing))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

