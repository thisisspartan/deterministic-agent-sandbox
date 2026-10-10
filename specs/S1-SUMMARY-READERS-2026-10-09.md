# S1 — readers of summary.json fields (grep audit, 2026-10-09)

> Precondition for the T3-4 rollback (cp → `--rm`). Every field a real reader
> consumes must still be produced after the rollback. Grep over the repo, no runs.

## 1. External readers (outside `launcher/`)

| Reader | Fields consumed | Source path |
|---|---|---|
| `.claude/e2e.sh` Gate 2 | `rc`, `verifier`, `probe_result`, `errors`, `failures` | `stanok/evidence/<label>/summary.json` |
| `.claude/commands/e2e.md` (protocol) | same as e2e.sh | same |
| `CLAUDE.supervisor.md` protocol (§3) | `rc`, `verifier`, `probe_result`, `contract_lock_violations`, `errors`, `failures`, `loop_trap` | same |
| `opik-traces.py` | `session_id` — passed as a CLI arg by the human, not read from summary | n/a |
| `launcher/hooks/loop-guard.py` | `session_id` — from the hook input JSON, not from summary | n/a |

No other scripts read summary.json: `launch.sh`, `doctor.sh`, `setup.sh`,
`scripts/run.sh` — none (verified by grep for `summary.json` / field names).
No token/turn accounting consumer exists in the repo.

## 2. Internal readers (launcher itself)

| Reader | Fields consumed |
|---|---|
| `cli._status_dict` (cli.py:222–259; `launch.sh status`/`wait`) | `rc`, `verifier`, `probe_result`, `turns`, `session_id`, `cache_hit_rate`, `elapsed_s`, `errors` — from the PUBLISHED summary |
| `cli.run_sandboxed` fresh-gate | presence of the worker summary (currently `cp_rc == 0`; after rollback: file presence in `LOG_DIR/<label>`) |
| `summary._publish_evidence` | the whole worker summary from `LOG_DIR/<label>` + `launcher.stdout.log` |

## 3. Fields with NO external reader (safe to remove in S2)

`worker_rc`, `worker_verifier`, `INTEGRITY-FAIL` — produced only inside
`summary._publish_evidence` (I5 detector); grep shows no consumer outside
`launcher/` and its tests.

## 4. Metadata precondition (verified on evidence/cc216-probe/summary.json)

`turns`, `inference_telemetry.per_turn`, token usage, `session_id`,
`commit_sha` all live INSIDE summary.json — written by the worker process into
`summary_dir`. After the rollback `summary_dir` (container) =
`LOG_DIR/<label>` via the existing rw mount → all metadata flows to the host
without `docker cp`. Nothing is lost by the rollback.

## 5. Verdict

Every consumed field is host-published after the rollback:
- verdict fields (`rc`/`verifier`/`probe_result`/`contract_lock_violations`/
  `errors`/`failures`) — host writes them in `_publish_evidence` (unchanged);
- telemetry fields — flow via the LOG_DIR mount (the worker writes them);
- missing summary after `--rm` → nothing published → `launch.sh status` reports
  `missing` = aborted run (supervisor protocol §3.3 handles it; no ENV-FAIL).

Rollback is safe to implement.
