# TASK-STANOK-CC-174 — Fix test_logdir_not_writable: assert the bwrap boundary, not the container boundary

edit: tests/test_adversarial_test.py
edit: docs/adversarial-probe-results.md
run.sh: exists

## Background

`test_logdir_not_writable` in `tests/test_adversarial_test.py` currently
asserts that the test process cannot write to `$STANOK_LOG_DIR` (default
`/tmp/stanok-logs`). That assertion is WRONG for this process: the test runs
OUTSIDE the model's bwrap sandbox (the external verifier spawns
`scripts/run.sh` as a direct subprocess of the container-side launcher), so it
sees the REAL log dir, which is rw BY DESIGN — the container-side launcher
writes `summary.json` / `launcher.stdout.log` there. The test therefore
asserts an impossible property and fails on every run, even when the model's
sandbox is correctly locked down.

The real I6 property: the model's bwrap-sandboxed Bash must not reach the real
log dir. That is enforced by `.claude/settings.stanok.json` listing the log
dir in `sandbox.filesystem.denyRead` — the CLI then mounts a throwaway tmpfs
over the dir inside every bwrap invocation, so model writes never persist to
the real dir. This was verified empirically on 2026-09-28 (run
`cc173-i6-verify`, see `docs/i6-verification.md`): from inside the sandbox the
dir appears empty, writes "succeed" per-invocation but never reach the host
dir.

## Task

Rewrite ONLY `test_logdir_not_writable` in `tests/test_adversarial_test.py`:

1. Compute the effective log dir:
   `logdir = os.environ.get("STANOK_LOG_DIR", "/tmp/stanok-logs")`.
2. Load `.claude/settings.stanok.json` (the test runs with cwd = repo root;
   read it relative to the repo root, e.g. via `os.path` from `__file__` or
   cwd — whichever is robust).
3. Assert the effective log dir (as an absolute path string) appears in BOTH
   `sandbox.filesystem.denyRead` AND `sandbox.filesystem.denyWrite`.
4. Keep the `_record(...)` call so `docs/adversarial-probe-results.md` is
   still regenerated: record the probe name, the path, `exists`
   (`os.path.isdir(logdir)`), a `writable` field set to `False` when the
   config assertion holds (the model's view is a throwaway tmpfs — it cannot
   write the real dir) and `True` otherwise, plus the error text (missing
   deny entry / unreadable settings) when it fails.
5. Update the test's docstring to state the boundary distinction explicitly:
   the MODEL's bwrap view of LOG_DIR is a throwaway tmpfs (denyRead), while
   this test process (verifier/launcher vantage point) sees the real rw dir by
   design — so the test asserts the CONFIG property, not its own writability.
   This prevents a future reader from "fixing" it back into a writability
   probe.

Do NOT change the other three tests in the file. Do NOT change the fixture or
the results-doc writer. Do NOT touch `.claude/`, `launcher/`, or `scripts/`.

## Acceptance

- `test_logdir_not_writable` PASSES with the current settings (which list
  `/tmp/stanok-logs` in both deny lists).
- The other 3 tests still pass (EROFS boundaries unchanged).
- `docs/adversarial-probe-results.md` is regenerated with the new record line
  (writable=False, error=None).
- The full suite is green.
