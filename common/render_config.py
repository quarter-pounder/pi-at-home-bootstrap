#!/usr/bin/env python3
"""Render domain templates using Jinja2."""

from __future__ import annotations

import argparse
import os
import re
import shutil
import subprocess
import sys
from pathlib import Path
from string import Template
from typing import Dict, Iterable

try:
    import yaml  # type: ignore[import]
except ImportError as exc:  # pragma: no cover - dependency hint
    print("[render] PyYAML not installed. Install with 'pip install -r requirements/render.txt'", file=sys.stderr)
    raise

try:
    from jinja2 import Environment, FileSystemLoader, StrictUndefined  # type: ignore[import]
except ImportError as exc:  # pragma: no cover - dependency hint
    print("[render] Jinja2 not installed. Install with 'pip install -r requirements/render.txt'", file=sys.stderr)
    raise


ROOT = Path(__file__).resolve().parents[1]
_MASK = re.compile(r"=[^=\n]+")


def mask_assignment(key: str, value: object) -> str:
    line = f"{key}={value}"
    return _MASK.sub("=<redacted>", line)


def log_info(message: str) -> None:
    print(f"[render] {message}")


def log_warn(message: str) -> None:
    print(f"[render][warn] {message}")


def parse_env_content(content: str) -> Dict[str, str]:
    data: Dict[str, str] = {}
    for raw_line in content.splitlines():
        line = raw_line.strip()
        if not line or line.startswith("#"):
            continue
        if "=" not in line:
            continue
        key, value = line.split("=", 1)
        key = key.strip()
        value = value.strip()
        if value.startswith(('"', "'")) and value.endswith(('"', "'")) and len(value) >= 2:
            value = value[1:-1]
        data[key] = value
    return data


def parse_env_file(path: Path) -> Dict[str, str]:
    if not path.exists():
        return {}
    return parse_env_content(path.read_text())


def decrypt_secrets(root: Path) -> Dict[str, str]:
    vault_file = root / "config-registry" / "env" / "secrets.env.vault"
    if not vault_file.exists():
        return {}
    if os.environ.get("VAULT_SKIP_DECRYPT"):
        log_warn("Skipping vault decryption (VAULT_SKIP_DECRYPT=1)")
        return {}
    if not shutil.which("ansible-vault"):
        log_warn("ansible-vault not found; skipping secrets.env.vault (see docs/operations/secrets.md)")
        return {}
    pass_file = root / ".vault_pass"
    if not pass_file.exists():
        log_warn(".vault_pass not found; skipping secrets.env.vault (see docs/operations/secrets.md)")
        return {}
    try:
        result = subprocess.run(
            [
                "ansible-vault",
                "view",
                str(vault_file),
                "--vault-password-file",
                str(pass_file),
            ],
            check=True,
            text=True,
            capture_output=True,
        )
    except subprocess.CalledProcessError as exc:
        log_warn(f"Unable to decrypt secrets.env.vault ({exc}); see docs/operations/secrets.md")
        return {}
    return parse_env_content(result.stdout)


def resolve_variables(env: Dict[str, str]) -> Dict[str, str]:
    resolved = dict(env)
    # iteratively resolve ${VAR} placeholders
    for _ in range(len(resolved) or 1):
        changed = False
        for key, value in list(resolved.items()):
            if not isinstance(value, str):
                continue
            new_value = Template(value).safe_substitute(resolved)
            if new_value != value:
                resolved[key] = new_value
                changed = True
        if not changed:
            break
    else:
        unresolved = [
            mask_assignment(key, value)
            for key, value in resolved.items()
            if isinstance(value, str) and "${" in value
        ]
        if unresolved:
            log_warn(
                "Possible circular reference in environment variable expansion: "
                + ", ".join(unresolved)
            )
    return resolved


def load_env_layers(root: Path, env_name: str) -> Dict[str, str]:
    base = parse_env_file(root / "config-registry" / "env" / "base.env")
    host = parse_env_file(root / ".env")
    overrides = parse_env_file(root / "config-registry" / "env" / "overrides" / f"{env_name}.env")
    secrets = decrypt_secrets(root)
    combined: Dict[str, str] = {}
    combined.update(base)
    combined.update(overrides)
    combined.update(host)
    combined.update(secrets)
    return resolve_variables(combined)


def load_ports(root: Path) -> Dict[str, Dict[str, int]]:
    ports_file = root / "config-registry" / "env" / "ports.yml"
    if not ports_file.exists():
        return {}
    data = yaml.safe_load(ports_file.read_text())
    return data or {}


def load_domains(root: Path) -> Iterable[Dict[str, object]]:
    domains_file = root / "config-registry" / "env" / "domains.yml"
    data = yaml.safe_load(domains_file.read_text()) if domains_file.exists() else {}
    return data.get("domains", []) if isinstance(data, dict) else []


def build_port_env_vars(ports: Dict[str, Dict[str, int]]) -> Dict[str, int]:
    env_vars: Dict[str, int] = {}
    for domain, mapping in ports.items():
        if not isinstance(mapping, dict):
            continue
        for name, value in mapping.items():
            if isinstance(value, int):
                key = f"PORT_{domain.upper()}_{name.upper()}"
                env_vars[key] = value
    return env_vars


TEMPLATE_SUFFIXES = {".tmpl", ".jinja", ".j2", ".jinja2"}


def derive_output_path(path: Path, root: Path) -> Path:
    relative = path.relative_to(root)
    candidate = relative
    while candidate.suffix in TEMPLATE_SUFFIXES:
        candidate = candidate.with_suffix("")
    return candidate


def render(domain: str, env_name: str, dry_run: bool = False) -> None:
    root = ROOT
    src = root / "domains" / domain / "templates"
    if not src.exists():
        log_warn(f"Template directory {src} not found; nothing to render")
        return

    dst = root / "generated" / domain
    dst.mkdir(parents=True, exist_ok=True)

    existing_files = {p for p in dst.rglob("*") if p.is_file()}
    generated_files: set[Path] = set()

    env_vars = load_env_layers(root, env_name)
    ports = load_ports(root)
    domains_data = list(load_domains(root))
    domain_entry = next((d for d in domains_data if d.get("name") == domain), {})

    context: Dict[str, object] = {}
    context.update(env_vars)
    context["ENV"] = env_name
    context["DOMAIN"] = domain
    context["domain"] = domain_entry
    context["ports"] = ports
    context.update(build_port_env_vars(ports))

    if domain == "registry" and not context.get("REGISTRY_HTTP_SECRET"):
        log_warn("REGISTRY_HTTP_SECRET is empty; token authentication will fail until it is set")

    log_info(f"Rendering {domain} for environment {env_name}")

    if dry_run:
        log_info("DRY-RUN: available context keys")
        for key in sorted(context):
            print(f"  {key}")
        return

    jinja_env = Environment(
        loader=FileSystemLoader(str(src)),
        autoescape=False,
        undefined=StrictUndefined,
        trim_blocks=True,
        lstrip_blocks=True,
    )

    template_files = sorted({p for suffix in TEMPLATE_SUFFIXES for p in src.rglob(f"*{suffix}")})
    if not template_files:
        log_warn(f"No templates matched (*.tmpl) in {src}")
        return

    changed = 0
    removed = 0
    unchanged = 0
    for template_path in template_files:
        template_name = template_path.relative_to(src).as_posix()
        template = jinja_env.get_template(template_name)
        try:
            output_text = template.render(**context)
        except Exception as exc:  # pragma: no cover - rendering failures
            log_warn(f"Render failed for {template_name}: {exc}")
            continue
        relative_output = derive_output_path(template_path, src)
        out_file = dst / relative_output
        generated_files.add(out_file)
        out_file.parent.mkdir(parents=True, exist_ok=True)
        if out_file.exists():
            existing_text = out_file.read_text()
            if existing_text == output_text:
                unchanged += 1
                continue
        out_file.write_text(output_text)
        if out_file in existing_files:
            log_info(f"updated {out_file.relative_to(root)}")
        else:
            log_info(f"created {out_file.relative_to(root)}")
        changed += 1

    stale_files = existing_files - generated_files
    for stale_file in sorted(stale_files):
        stale_file.unlink()
        log_info(f"removed {stale_file.relative_to(root)}")
        removed += 1

    # clean up empty directories left behind after removing stale files
    empty_dirs = sorted({p for p in dst.rglob("*") if p.is_dir()}, reverse=True)
    for directory in empty_dirs:
        try:
            next(directory.iterdir())
        except StopIteration:
            directory.rmdir()

    if changed == 0 and removed == 0:
        log_info(f"No changes for {domain}")
    else:
        if unchanged:
            log_info(f"{unchanged} files unchanged for {domain}")


def main() -> None:
    parser = argparse.ArgumentParser(description="Render domain templates")
    parser.add_argument("--domain", required=True, help="Domain name (matches folder under domains/)")
    parser.add_argument("--env", default="dev", help="Environment override to load")
    parser.add_argument("--dry-run", action="store_true", help="Print available context keys and exit")
    args = parser.parse_args()

    try:
        render(args.domain, args.env, dry_run=args.dry_run)
    except FileNotFoundError as exc:
        log_warn(str(exc))
        sys.exit(1)


if __name__ == "__main__":
    main()

