# TASK-STANOK-CC-071 — Native-first deletion: the hand-rolled event stream

Supervisor-executed (NOT a machine task). Follow-up to the red team on
`specs/ADR-agent-view.md` (`specs/REDTEAM-VERDICT-agent-view.md`, R2).

## Finding (verified, read-only)

The machine writes a hand-rolled per-run event log — `emit()` appends
`/tmp/stanok-logs/<label>/events.jsonl`; the `watch` subcommand
(`cmd_watch`) tails it. **Nothing consumes it:**

- `grep -rn 'events.jsonl|cmd_watch' --include='*.sh' --include='*.py'
  --include='*.md' /home/hermes/darkcast` → only `stanok.py` (writer +
  `cmd_watch`) and `stanok/README.md` (doc). No other caller.
- The supervisor role forbids log reading while running
  (`CLAUDE.supervisor.md` §3: "categorically FORBIDDEN to read … logs while
  the machine is running") and waits via `status` + `summary.json` only.
- `hooks/verifier.sh`'s `emit()` is an unrelated shell JSON helper.
- `watch` is dispatched only from `launch.sh:29`; the supervisor never calls it.

`events.jsonl` lives in `/tmp/stanok-logs/<label>/` (ephemeral `_live_dir`),
so it is not part of the evidence contract; `summary.json` is written
independently of `emit()`.

## Change

Delete the dead hand-rolled event stream. Native `status`/`summary.json` (and
the raw `session-<run_id>.jsonl` SDK stream dump) already cover the need.

- `launcher/stanok.py`
  - remove `emit()` and the `_events_path` global + its assignment
  - remove the 7 `emit(...)` call sites (job.start, session.resolved,
    session.start, turn.start, turn.tokens, verifier, summary)
  - remove `cmd_watch()` and the `watch` subparser + dispatch
  - KEEP `session-<run_id>.jsonl` (`_write_stream_msg`) and `_live_dir` —
    the raw SDK stream is the only transcript that escapes the sandbox
    (host `~/.claude/projects` is inside the tmpfs HOME), and it has no
    replacement cost.
  - KEEP `status`/`stop`/`.running`/`check-dirty` (the ADR's irreducible set).
- `launch.sh` — remove `watch` from the control dispatch (line 29) and usage.
- `README.md` — remove the `watch` row and drop `watch` from the Runner blurb.

## Explicit non-change (recorded so it is not re-litigated)

R2 item 1 suggested replacing role injection in `P0-launch.sh` with the native
`agent` setting / `--agents`. **Not done:** `P0-launch.sh:189` already uses the
native flag `--append-system-prompt-file "$ROLE_FILE"` — there is no hand-rolled
plumbing to delete, and `agent`/`--agents` are a *different* mechanism
(replace main-thread system prompt + tool restrictions + model) that would
change behavior. `P0-launch.sh` is byte-identical in `darkcast` and
`skeleton-pub`; changing it is out of scope.

## Acceptance

- `py_compile` clean; `bash -n launch.sh` clean.
- `grep -rn 'events.jsonl|cmd_watch' stanok/` → 0 hits.
- `python launcher/stanok.py watch x` → argparse: invalid choice 'watch'
  (choices: run, status, stop, check-dirty). `./stanok/launch.sh watch x` no
  longer routes to python (fails closed: dirty-tree rc=22 / ticket-not-found
  rc=13) — the subcommand is gone, not silently accepted.
- `./stanok/launch.sh status <label>` still returns the same JSON shapes.
- `hooks/doctor.sh` on a clean tree: all ok.
