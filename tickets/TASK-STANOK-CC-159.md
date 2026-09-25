# TASK-STANOK-CC-159 — Opik trace-diagnosis helper (client-side filter)

Executor: **operator/supervisor** (new script in the supervisor zone, root).
NOT a machine ticket.

## Incident (citation, per §7)

2026-09-25, FIRE-batch analysis: one-off Opik fetches with query params
`search=<session_id>`, `thread_id=<sid>`, `startTime`/`endTime` ALL returned
the unfiltered total (`total: 3385`) — the self-hosted Opik API
(`http://localhost:5173/api/v1/private/traces?project_id=01a09a5b-4791-72c3-8a01-15ceebf0b48a`)
silently ignores unknown parameters. Verifying 6 sessions required
hand-rolled pagination over 34 pages of 100, filtering
`metadata.thread_id` client-side. The first attempt (curl loop with
`search=`) returned empty and looked like a failure.

## Requirements

1. A supervisor-zone script (e.g. `opik-traces.py` at the root, stdlib only):
   - args: one or more session (thread) IDs; optional `--project`
     (default `01a09a5b-4791-72c3-8a01-15ceebf0b48a`), `--base`
     (default `http://localhost:5173`).
   - paginates `/api/v1/private/traces?project_id=...&size=100&page=N` and
     filters `metadata.thread_id` in-process.
   - per session prints: trace count, min/max `start_time`, and the final
     trace's `output.response.model_output` (truncated) + `metadata.success`.
   - exits non-zero if a session has zero traces.
2. `CLAUDE.supervisor.md` §6 note: one-off trace fetches AFTER a run use this
   helper; never poll while the machine runs (existing rule stays).
3. No Opik server change (self-hosted upstream; out of scope).

## Acceptance

- Run against the 6 FIRE session IDs
  (`27c96b22…`, `291de34a…`, `c8ff0500…`, `281c60ab…`, `beae2296…`,
  `bfe17bc0…`) reproduces: 25/46/39/41/65/32 traces, windows
  14:29–15:23 UTC, all `success=True`.
- Unknown session ID → non-zero exit, clear message.
