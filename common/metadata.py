#!/usr/bin/env python3
"""Metadata management CLI (generate, diff, commit, check)."""

from __future__ import annotations

import argparse
import datetime as dt
import difflib
import fcntl
import hashlib
import os
import subprocess
import sys
from pathlib import Path
from typing import Any, Dict, Iterable, List, Tuple

import yaml

ROOT = Path(__file__).resolve().parents[1]
STATE_DIR = ROOT / "config-registry" / "state"
CACHE_DIR = STATE_DIR / "metadata-cache"
DOMAINS_FILE = ROOT / "config-registry" / "env" / "domains.yml"
PORTS_FILE = ROOT / "config-registry" / "env" / "ports.yml"
LOCK_FILE = STATE_DIR / ".lock"


def log_info(message: str) -> None:
    print(f"[metadata] {message}")


def log_warn(message: str) -> None:
    print(f"[metadata][warn] {message}")


def current_git_commit() -> str:
    try:
        return (
            subprocess.check_output(
                ["git", "rev-parse", "--short", "HEAD"],
                cwd=str(ROOT),
                text=True,
                stderr=subprocess.DEVNULL,
            )
            .strip()
            or "unknown"
        )
    except Exception:
        return "unknown"


def file_sha256(path: Path) -> str:
    h = hashlib.sha256()
    h.update(path.read_bytes())
    return h.hexdigest()


def compute_source_hash(files: Iterable[Path]) -> str:
    lines = []
    for path in files:
        if path.exists():
            digest = file_sha256(path)
            rel = path.relative_to(ROOT)
            lines.append(f"{digest}  {rel.as_posix()}\n")
    joined = "".join(lines).encode()
    return hashlib.sha256(joined).hexdigest()


def template_hash(domain: str) -> str | None:
    base = ROOT / "domains" / domain / "templates"
    if not base.exists():
        return None
    paths = sorted(base.rglob("*.tmpl"))
    if not paths:
        return None
    h = hashlib.sha256()
    for path in paths:
        h.update(path.read_bytes())
    return h.hexdigest()


def load_yaml(path: Path) -> Any:
    if not path.exists():
        return {}
    return yaml.safe_load(path.read_text()) or {}


def load_domains() -> List[Dict[str, Any]]:
    data = load_yaml(DOMAINS_FILE)
    if isinstance(data, dict):
        return data.get("domains", []) or []
    return []


def load_ports() -> Dict[str, Dict[str, Any]]:
    data = load_yaml(PORTS_FILE)
    return data if isinstance(data, dict) else {}


def domain_entry(domains: List[Dict[str, Any]], name: str) -> Dict[str, Any]:
    for entry in domains:
        if entry.get("name") == name:
            return entry
    return {}


def is_managed_externally(entry: Dict[str, Any]) -> bool:
    return bool(entry.get("managed_externally"))


def generate_domain_metadata(
    entry: Dict[str, Any],
    ports: Dict[str, Dict[str, Any]],
    source_hash: str,
    git_commit: str,
) -> Dict[str, Any]:
    name = entry["name"]
    metadata: Dict[str, Any] = {
        "_meta": {
            "generated_at": dt.datetime.now(dt.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
            "git_commit": git_commit,
            "source_hash": source_hash,
            "domain": name,
        },
        "name": name,
        "placement": entry.get("placement", "local"),
        "standalone": bool(entry.get("standalone", False)),
        "requires": entry.get("requires", []) or [],
        "exposes_to": entry.get("exposes_to", []) or [],
        "consumes": entry.get("consumes", []) or [],
        "networks": [f"{name}-network"],
    }
    description = entry.get("description")
    if description:
        metadata["description"] = description

    if is_managed_externally(entry):
        metadata["managed_externally"] = True

    tmpl_hash = template_hash(name)
    if tmpl_hash:
        metadata["_meta"]["template_hash"] = tmpl_hash

    domain_ports = ports.get(name)
    if isinstance(domain_ports, dict) and domain_ports:
        metadata["ports"] = domain_ports

    return metadata


def write_metadata(domain: str, data: Dict[str, Any]) -> bool:
    CACHE_DIR.mkdir(parents=True, exist_ok=True)
    cache_path = CACHE_DIR / f"{domain}.yml"
    new_content = yaml.safe_dump(data, sort_keys=False)
    if cache_path.exists() and cache_path.read_text() == new_content:
        return False
    cache_path.write_text(new_content)
    log_info(f"Updated {cache_path.relative_to(ROOT)}")
    return True


def remove_stale_cache(domains: Iterable[str]) -> None:
    existing = {f.stem for f in CACHE_DIR.glob("*.yml")}
    keep = set(domains)
    for stale in existing - keep:
        path = CACHE_DIR / f"{stale}.yml"
        log_warn(f"Removing stale cache: {path.relative_to(ROOT)}")
        path.unlink(missing_ok=True)


def locked(func, *args, **kwargs):
    LOCK_FILE.parent.mkdir(parents=True, exist_ok=True)
    with LOCK_FILE.open("w") as lock:
        try:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            log_warn("Metadata generation already running")
            return
        try:
            return func(*args, **kwargs)
        finally:
            fcntl.flock(lock, fcntl.LOCK_UN)


def cmd_generate(args: argparse.Namespace) -> None:
    domains = load_domains()
    ports = load_ports()
    git_commit = current_git_commit()
    source_hash = compute_source_hash([DOMAINS_FILE, PORTS_FILE])

    def _generate():
        updated_any = False
        for entry in domains:
            name = entry.get("name")
            if not name:
                continue
            metadata = generate_domain_metadata(entry, ports, source_hash, git_commit)
            updated = write_metadata(name, metadata)
            updated_any = updated_any or updated
        remove_stale_cache([str(d["name"]) for d in domains if d.get("name")])
        if not updated_any:
            log_info("Metadata cache already up to date")

    locked(_generate)


def load_metadata(path: Path) -> Dict[str, Any]:
    if not path.exists():
        return {}
    data = yaml.safe_load(path.read_text()) or {}
    if isinstance(data, dict):
        data = data.copy()
        meta = data.get("_meta")
        if isinstance(meta, dict):
            meta = meta.copy()
            meta.pop("generated_at", None)
            data["_meta"] = meta
    return data


def diff_domain(domain: str, canonical: Path, cache: Path) -> Tuple[bool, str]:
    canon_data = load_metadata(canonical)
    cache_data = load_metadata(cache)
    if canon_data == cache_data:
        return False, ""
    canon_dump = yaml.safe_dump(canon_data, sort_keys=False).splitlines()
    cache_dump = yaml.safe_dump(cache_data, sort_keys=False).splitlines()
    diff_lines = list(
        difflib.unified_diff(
            canon_dump,
            cache_dump,
            fromfile=str(canonical.relative_to(ROOT)),
            tofile=str(cache.relative_to(ROOT)),
            lineterm="",
        )
    )
    return True, "\n".join(diff_lines)


def cmd_diff(args: argparse.Namespace) -> int:
    domains = load_domains()
    diff_found = False
    for entry in domains:
        name = entry.get("name")
        if not name:
            continue
        if is_managed_externally(entry):
            log_info(f"Skipping metadata diff for {name} (managed externally)")
            continue
        canonical = ROOT / "domains" / name / "metadata.yml"
        cache = CACHE_DIR / f"{name}.yml"
        if canonical.exists() and cache.exists():
            has_diff, diff_text = diff_domain(name, canonical, cache)
            if has_diff:
                diff_found = True
                if diff_text:
                    print(diff_text)
        elif cache.exists() and not canonical.exists():
            log_warn(f"Missing metadata for {name} (new domain?)")
            diff_found = True
    if not diff_found:
        log_info("No metadata drift detected")
    return 1 if diff_found else 0


def cmd_commit(args: argparse.Namespace) -> None:
    cmd_generate(args)
    domains = load_domains()
    for entry in domains:
        name = entry.get("name")
        if not name:
            continue
        if is_managed_externally(entry):
            log_info(f"Skipping metadata commit for {name} (managed externally)")
            continue
        cache = CACHE_DIR / f"{name}.yml"
        target = ROOT / "domains" / name / "metadata.yml"
        if not cache.exists():
            continue
        target.parent.mkdir(parents=True, exist_ok=True)
        if not target.exists() or cache.read_text() != target.read_text():
            target.write_text(cache.read_text())
            log_info(f"Updated {target.relative_to(ROOT)}")
        else:
            log_info(f"No changes for {name}")


def cmd_check(args: argparse.Namespace) -> int:
    cmd_generate(args)
    return cmd_diff(args)


def parse_args(argv: list[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Metadata cache management")
    sub = parser.add_subparsers(dest="command", required=True)

    sub.add_parser("generate", help="Generate metadata cache files")
    sub.add_parser("diff", help="Show drift between cache and canonical metadata")
    sub.add_parser("commit", help="Copy cache to canonical metadata files")
    sub.add_parser("check", help="Generate then fail if drift detected")

    return parser.parse_args(argv)


def main(argv: list[str] | None = None) -> int:
    args = parse_args(argv or sys.argv[1:])
    if args.command == "generate":
        cmd_generate(args)
        return 0
    if args.command == "diff":
        return cmd_diff(args)
    if args.command == "commit":
        cmd_commit(args)
        return 0
    if args.command == "check":
        return cmd_check(args)
    return 1


if __name__ == "__main__":
    sys.exit(main())

