# CONTEXT — persistent project facts

## Topology
- Root: `CLAUDE.supervisor.md`, `CONTEXT.md`, `P0-launch.sh`, `specs/`, `tickets/`, `stanok/`.
- Supervisor zone: `CONTEXT.md`, `specs/`, `tickets/`.
- Machine zone: `stanok/` (git submodule, isolated execution).

## Server
- URL: `http://127.0.0.1:8080` (overridden by `STANOK_SERVER_URL` in `P0-launch.sh`).
- Model: `Qwen3.8-27B-MTP` (overridden by `STANOK_MODEL`).
- Single slot (`--parallel 1`): supervisor and machine never run simultaneously.

## Tickets
- Next free number: **001**.
- Format: `tickets/TASK-STANOK-CC-NNN.md`.

## Known limitations
- `TURN_TIMEOUT_S` = 1200 (default in `stanok/launcher/stanok.py`, override `STANOK_TURN_TIMEOUT_S`).
- Machine launch only on a clean `git -C stanok status --porcelain` (otherwise rc=22).
- Waiting — only via the blocking `while ./stanok/launch.sh status <label> | grep -q '"state": "running"'; do sleep 15; done` in a single Bash command.
