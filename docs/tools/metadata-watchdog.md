# Metadata Watchdog

A lightweight controller monitors `config-registry/state/metadata-cache/*.yml` and alerts when cached metadata diverges from the committed canonical files under `domains/<name>/metadata.yml`.

## Goals
- Surface drift immediately after `generate-metadata` produces new cache files.
- Nudge developers to review (`make diff-metadata`) and commit (`make commit-metadata`).
- Keep the workflow manual-first; no auto-commits.

## Behaviour
1. Watch directory `config-registry/state/metadata-cache/` using `watchdog` (Python) or `inotify`.
2. Debounce rapid write events (multiple notifications per save).
3. On change:
   - For each touched cache file, compare with `domains/<name>/metadata.yml`.
   - If different, log a warning and optionally print the unified diff (`make diff-metadata`).
   - If identical, ignore.
4. Exit cleanly on SIGINT/SIGTERM.

## Implementation Sketch
- Script: `tools/metadata_watchdog.py` (run from repo root).
- Dependencies: `watchdog` (preferred) or `inotify_simple`. List requirement in `requirements/watchdog.txt`.
- Logging: reuse `common/utils.py` logging helpers or simple `print`.
- CLI options:
  - `--once` (run diff once and exit)
  - `--auto-diff` (run `make diff-metadata` automatically and stream output)

## Future Enhancements
- Auto-trigger `make generate-metadata` before diffing.
- Integrate with desktop notifications or Slack webhook.
- Persist last-notified state to avoid repeated alerts on unchanged diffs.

Until implemented, run `python3 pi-forge/tools/metadata_watchdog.py` in a tmux pane while editing metadata.

## Systemd Unit Example
```
[Unit]
Description=Pi Forge Metadata Drift Watchdog

[Service]
ExecStart=/usr/bin/python3 /home/pi/pi-forge/pi-forge/tools/metadata_watchdog.py --auto-diff
WorkingDirectory=/home/pi/pi-forge
Restart=always
Environment=ENABLE_COMMON_TRAP=0

[Install]
WantedBy=multi-user.target
```

### Notes
- Uses a flock at `config-registry/state/.lock` to avoid races with CI.
- Debounces events; exits quietly if another instance holds the lock.
- `--auto-diff` runs `make diff-metadata` to print the diff automatically.
