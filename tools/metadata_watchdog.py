#!/usr/bin/env python3
"""
Metadata Watchdog

Monitors config-registry/state/metadata-cache/ for changes and alerts on metadata drift.
"""

from __future__ import annotations

import argparse
import logging
import os
import shutil
import signal
import subprocess
import sys
import threading
import time
from contextlib import contextmanager
from pathlib import Path

try:
    import fcntl
except ImportError:  # pragma: no cover (Windows or constrained systems)
    fcntl = None  # type: ignore

# ---------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------
ROOT_DIR = Path(__file__).resolve().parents[1]
WATCH_DIR = ROOT_DIR / "config-registry/state/metadata-cache"
LOCK_FILE = ROOT_DIR / "config-registry/state/.lock"
METADATA_SCRIPT = ROOT_DIR / "common" / "metadata.py"
PYTHON = shutil.which("python3") or "python3"

LOG_FORMAT = "%(asctime)s [%(levelname)s] %(message)s"
logging.basicConfig(level=logging.INFO, format=LOG_FORMAT)
logger = logging.getLogger("metadata_watchdog")


# ---------------------------------------------------------------------
# Locking
# ---------------------------------------------------------------------
@contextmanager
def metadata_lock(non_blocking: bool = True):
    """Prevent concurrent metadata generation."""
    if fcntl is None:
        yield
        return
    LOCK_FILE.parent.mkdir(parents=True, exist_ok=True)
    with LOCK_FILE.open("w") as handle:
        flags = fcntl.LOCK_EX | (fcntl.LOCK_NB if non_blocking else 0)
        try:
            fcntl.flock(handle, flags)
        except OSError:
            raise RuntimeError("lock-unavailable")
        try:
            yield
        finally:
            fcntl.flock(handle, fcntl.LOCK_UN)


# ---------------------------------------------------------------------
# Core functionality
# ---------------------------------------------------------------------
def run_metadata_diff(auto_diff: bool) -> None:
    """Run metadata diff and optionally trigger make diff-metadata."""
    try:
        with metadata_lock():
            proc = subprocess.run(
                [PYTHON, str(METADATA_SCRIPT), "diff"],
                cwd=ROOT_DIR,
                check=False,
                text=True,
                capture_output=True,
            )
    except RuntimeError:
        logger.info("Another metadata operation is running; skipping diff")
        return

    stdout = proc.stdout.strip()
    if proc.returncode != 0:
        logger.warning("Metadata drift detected")
        if stdout:
            for line in stdout.splitlines():
                logger.info(line)
        if auto_diff:
            if shutil.which("make"):
                logger.info("Running make diff-metadata…")
                subprocess.run(
                    ["make", "-C", str(ROOT_DIR), "diff-metadata"],
                    cwd=ROOT_DIR,
                )
            else:
                logger.error("'make' not found; cannot auto-diff")
    else:
        if stdout:
            for line in stdout.splitlines():
                logger.info(line)
        logger.info("No metadata drift detected")


def run_once(auto_diff: bool) -> None:
    if not WATCH_DIR.exists():
        logger.warning("%s does not exist", WATCH_DIR)
    run_metadata_diff(auto_diff)


# ---------------------------------------------------------------------
# Polling and watchdog modes
# ---------------------------------------------------------------------
def poll_loop(auto_diff: bool, interval: float) -> None:
    """Fallback mode when watchdog is unavailable."""
    WATCH_DIR.mkdir(parents=True, exist_ok=True)
    last_state: dict[str, float] = {}
    logger.info("Polling %s every %.1fs", WATCH_DIR, interval)
    try:
        while True:
            current = {str(p): p.stat().st_mtime for p in WATCH_DIR.glob("*.yml")}
            if current != last_state:
                last_state = current
                run_metadata_diff(auto_diff)
            time.sleep(interval)
    except KeyboardInterrupt:
        logger.info("Stopping metadata watchdog")


def watchdog_loop(auto_diff: bool, debounce: float) -> None:
    """Event-driven loop using watchdog."""
    from watchdog.events import FileSystemEventHandler
    from watchdog.observers import Observer

    class Handler(FileSystemEventHandler):
        def on_any_event(self, event):
            if not event.is_directory and event.src_path.endswith(".yml"):
                signal_event()

    event = threading.Event()

    def worker():
        while True:
            event.wait()
            time.sleep(debounce)
            event.clear()
            run_metadata_diff(auto_diff)

    def signal_event():
        event.set()

    observer = Observer()
    WATCH_DIR.mkdir(parents=True, exist_ok=True)
    observer.schedule(Handler(), str(WATCH_DIR), recursive=False)
    observer.start()
    threading.Thread(target=worker, daemon=True).start()
    logger.info("Watching %s (auto_diff=%s)", WATCH_DIR, auto_diff)
    try:
        while True:
            time.sleep(1)
    except KeyboardInterrupt:
        logger.info("Stopping metadata watchdog")
    finally:
        observer.stop()
        observer.join()


# ---------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------
def have_watchdog() -> bool:
    try:
        import watchdog.events  # noqa: F401
        import watchdog.observers  # noqa: F401
        return True
    except Exception:
        return False


def parse_args(argv: list[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Metadata drift watchdog")
    parser.add_argument("--auto-diff", action="store_true", help="Run make diff-metadata on drift")
    parser.add_argument("--once", action="store_true", help="Run one diff/check and exit")
    parser.add_argument("--debounce", type=float, default=1.0, help="Debounce interval for watchdog")
    parser.add_argument("--interval", type=float, default=3.0, help="Polling interval if watchdog not installed")
    return parser.parse_args(argv)


# ---------------------------------------------------------------------
# Entrypoint
# ---------------------------------------------------------------------
def main(argv: list[str]) -> int:
    args = parse_args(argv)

    def handle_exit(sig, frame):  # noqa: ARG001
        raise KeyboardInterrupt

    signal.signal(signal.SIGTERM, handle_exit)

    if args.once:
        run_once(args.auto_diff)
        return 0

    if have_watchdog():
        watchdog_loop(args.auto_diff, max(0.2, args.debounce))
    else:
        logger.warning("watchdog package not installed; falling back to polling")
        poll_loop(args.auto_diff, max(1.0, args.interval))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
