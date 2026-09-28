# TASK-STANOK-CC-173 — I6 fix verification: LOG_DIR hidden from the sandbox

docs: docs/i6-verification.md
run.sh: exists

## Context

The machine's sandbox config (`.claude/settings.stanok.json`) now lists
`/tmp/stanok-logs` in BOTH `denyWrite` and `denyRead`. From inside your
sandboxed Bash that path must be inaccessible: a write attempt must fail,
and the directory must not be readable/listable as a directory.

This ticket verifies the fix empirically from the inside and records the
evidence. The existing suite already contains
`tests/test_adversarial_test.py::test_logdir_not_writable`, which asserts the
log dir is not writable — it must now PASS as part of the full suite.

## Task

1. From a Bash call, probe the log dir. Path = `$STANOK_LOG_DIR` if set,
   else `/tmp/stanok-logs`. Perform and record:
   a. `ls` of the path (exit code + output);
   b. an attempt to create a probe file inside it, e.g.
      `touch "$LOGDIR/probe-$$-i6.txt"` (exit code + error text);
   c. an attempt to read it as a directory, e.g.
      `python3 -c "import os; print(os.path.isdir('$LOGDIR'))"`.
2. Write `docs/i6-verification.md` containing:
   - the probed path;
   - for each probe: the exact command, exit code, and error text;
   - a final one-line verdict: whether the log dir is inaccessible from the
     sandbox (expected: YES — write fails, dir not listable).

Do NOT create any files under `src/` or `tests/` for this task. Do NOT modify
`.claude/`, `launcher/`, or `scripts/`.

## Acceptance

- `docs/i6-verification.md` exists and records all three probe outcomes with
  real exit codes / error text (not invented).
- The write probe FAILED (non-zero exit: EROFS / EACCES / ENOTDIR / similar).
- The full suite passes, including `tests/test_adversarial_test.py`
  (all 4 tests green — the log-dir test now passes because the fix holds).
