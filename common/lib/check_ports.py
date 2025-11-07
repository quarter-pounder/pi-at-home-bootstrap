#!/usr/bin/env python3

import json
import subprocess
import sys


def load_ports() -> dict:
    try:
        raw = subprocess.check_output(
            ["yq", "-o=json", "config-registry/env/ports.yml"],
            text=True,
        )
    except subprocess.CalledProcessError as exc:
        sys.exit(exc.returncode)

    raw = raw.strip()
    if not raw:
        return {}
    return json.loads(raw)


def main() -> int:
    data = load_ports()
    conflicts: list[str] = []
    by_port: dict[int, list[str]] = {}

    if isinstance(data, dict):
        for domain, ports in data.items():
            if not isinstance(ports, dict):
                continue
            for name, value in ports.items():
                if isinstance(value, int):
                    if not (1 <= value <= 65535):
                        conflicts.append(f"Port {value} in {domain}.{name} is out of valid range")
                        continue
                    by_port.setdefault(value, []).append(f"{domain}.{name}")

    for port in sorted(by_port):
        mappings = by_port[port]
        if len(mappings) > 1:
            conflicts.append(f"Port {port} used by {', '.join(mappings)}")

    if conflicts:
        print("\n".join(conflicts))

    return 0


if __name__ == "__main__":
    sys.exit(main())

