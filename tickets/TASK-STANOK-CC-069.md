# TASK-STANOK-CC-069 — Dirty-tree gate: 4 copies → 1 (item 3/3)

## Problem
The clean-tree precondition (SEC-01) was implemented four times, each with its own
exit code and message:

1. `launch.sh` — inline `git -C "$STANOK_ROOT" status --porcelain` → `exit 22`.
2. `stanok.py::dirty_tree_gate()` — same check, called from `main()` → `early_abort(22)`.
3. `stanok.py::reset_repo()` — a *third* copy of the same check inside the runner
   (→ rc=14 with a "host-side gate did not run" message).
4. `.claude/e2e.sh` Gate 1 — same check again (→ `exit 1`, different code).

Four places to keep in sync; three different codes for one condition.

## Change
Single source: `dirty_tree_gate()` in `stanok.py`.

- **`stanok.py`**
  - `reset_repo()` → **`prepare_workspace()`**: the duplicate git-status block is
    deleted; it now only creates `src/tests/docs` and unfreezes `tests/`
    (`chmod -R u+w`). Returns 0/14 for workspace-prep errors only.
  - New `check-dirty` subcommand: `return 22 if dirty_tree_gate() else 0`
    (no side effects, pure stdlib, works with system python3).
- **`launch.sh`**: inline check replaced by `"$PY" "$STANOK_PY" check-dirty`;
  on non-zero → the same rc=22 message.
- **`.claude/e2e.sh`**: Gate 1 deleted; relies on launch.sh rc=22.
- Comments updated: `sandbox-run.sh`, `hooks/verifier.sh`, `CONTEXT.md`,
  `.claude/commands/e2e.md`.

Net: one implementation, one condition, rc=22 everywhere.

## Behavior
Identical on all reachable paths: dirty tree → rc=22 before pre-flight/lock;
the in-runner copy only ever fired when the host gate was bypassed (it no longer
has a path to fire, since `main()` still checks at 898 and launch.sh checks first).

## Files
- `stanok/launcher/stanok.py`
- `stanok/launch.sh`
- `.claude/e2e.sh`
- `stanok/sandbox-run.sh`, `stanok/hooks/verifier.sh` (comments only)
- `CONTEXT.md`, `.claude/commands/e2e.md` (docs)

## Smoke
Operator runs `hooks/doctor.sh` on the clean submodule — it must still report:
`ok runner dirty-tree (uncommitted file -> rc=22)` (test 2b), plus
`ok runner fail-fast (dead server -> rc=20)` (test 2) and the label-guard (rc=15).

## Acceptance
- `bash -n` clean on launch.sh / sandbox-run.sh / verifier.sh / e2e.sh.
- `py_compile` clean on stanok.py.
- Manual: dirty submodule → `launch.sh run` exits 22 with no side effects.
- `hooks/doctor.sh`: dirty-tree rc=22 and dead-server rc=20 still hold.
