# TASK-STANOK-CC-158 — Supervisor launch discipline: absolute paths, no cwd drift

Executor: **operator/supervisor** (process + `CLAUDE.supervisor.md`; no launcher code).
NOT a machine ticket.

## Incident (citation, per §7)

2026-09-25, FIRE-01 launch 4: an earlier `sed` command had changed the
supervisor shell cwd to `tickets/`. The next launch used the relative path
`./stanok/launch.sh` → `exit 127: no such file or directory`; the follow-up
`git -C stanok status` also failed (`fatal: cannot change to 'stanok'`).
Two tool calls burned diagnosing a cwd drift.

Note: `stanok/launch.sh` is ALREADY self-locating (`DIR="$(cd "$(dirname
"$0")" && pwd)"; cd "$DIR"`) — the failure is entirely in the path used to
REACH launch.sh, so the fix is supervisor-side, not launcher-side.

## Requirements

1. `CLAUDE.supervisor.md` §3 (pipeline) must state: launch and all
   `git -C` / evidence reads use ABSOLUTE paths
   (`/home/hermes/darkcast/stanok/launch.sh`, `git -C /home/hermes/darkcast/stanok`),
   or the supervisor verifies `pwd` == project root before any relative call.
2. The gate procedure in §2 (clean-tree check before launch) must use the
   absolute `git -C` form so it cannot be broken by cwd drift.
3. No launcher change (verified: launch.sh already `cd "$DIR"`).

## Acceptance

- `CLAUDE.supervisor.md` contains the absolute-path rule in §2 and §3.
- From an arbitrary cwd (e.g. `tickets/`), the documented launch command
  works verbatim.
