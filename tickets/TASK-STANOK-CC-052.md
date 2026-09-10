# TASK-STANOK-CC-052 — P0-launch.sh: `--host` flag, no hardcoded server IP, skeleton-pub sync

Status: `[x] DONE` (executed by the supervisor on the host — infrastructure change, not project code)

## 1. P0-launch.sh — `--host <ip>` flag

- New CLI flag: `./P0-launch.sh [--host <ip>] [claude arguments]` (default host `127.0.0.1`).
- `SERVER_URL` / `PROXY` / `no_proxy` are derived from the host: `http://$HOST:8080`,
  `http://$HOST:8118`, `$HOST,localhost,127.0.0.1`. Env overrides (`STANOK_SERVER_URL`,
  `STANOK_PROXY`) still win.
- `STANOK_SERVER_URL` / `STANOK_PROXY` are exported, so the machine
  (`stanok/launcher/stanok.py` reads them from the environment, default `127.0.0.1`)
  inherits the endpoint — no code change in `stanok/`.
- `CLAUDE_BIN` / `SEARCH_ENV_FILE` defaults switched to `$HOME`-based paths.
- The server IP is no longer hardcoded in the code — it is passed as
  `--host 192.168.8.131` (see CONTEXT.md).

## 2. Sync with skeleton-pub

- `P0-launch.sh` is now byte-identical in `darkcast` and `skeleton-pub` (`diff` empty).

## Smokes

- `bash -n P0-launch.sh` — both repos OK.
- `diff darkcast/P0-launch.sh skeleton-pub/P0-launch.sh` — empty.
- Flag smoke (fake `CLAUDE_BIN=/bin/echo`): `--host 10.0.0.5 --foo bar` →
  endpoint `http://10.0.0.5:8080`, claude args passed through; no flag →
  `http://127.0.0.1:8080`; `--host` without a value → explicit error.
- `git status --porcelain` — both trees clean.
