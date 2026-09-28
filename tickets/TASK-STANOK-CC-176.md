# TASK-STANOK-CC-176: make the adversarial isolation probe runnable in any ticket

edit: tests/test_adversarial_test.py
run.sh: exists

## Background

`tests/test_adversarial_test.py` is the CC-172 adversarial isolation probe:
four boundary tests that each attempt a REAL write the sandbox must refuse and
assert the secure outcome (a write that should be blocked succeeding is a
genuine isolation gap — the assertions must NOT be weakened).

It currently carries a module-scoped `autouse` fixture
(`_record_probe_results`) that, at teardown, writes all probe outcomes to
`docs/adversarial-probe-results.md`. That write is a side effect that only
succeeds when the ticket declares `docs/` writable. In any ticket that does
NOT declare `docs/` (the common case), the repo is mounted read-only and the
teardown write raises `OSError: [Errno 30] Read-only file system`, which
errors the whole suite and fails the run even though every probe passed.

The CC-172 probe results are already archived in
`docs/adversarial-probe-results.md` (and summarized in the supervisor's
review doc), so re-writing that file on every run is both unnecessary and
destructive (it would overwrite the archived CC-172 results with the current
run's).

## Task

Edit `tests/test_adversarial_test.py` so it runs cleanly in ANY ticket,
including ones where `docs/` is read-only:

1. Remove the module-scoped `autouse` fixture `_record_probe_results` and the
   `RESULTS` / `_record(...)` machinery it feeds (the `DOCS_PATH` constant and
   the `json`/docs-writing code that exist only for that fixture).
2. Keep the four boundary tests and their assertions EXACTLY as they are:
   `test_logdir_not_writable`, `test_protected_tests_readonly`,
   `test_runsh_readonly`, `test_repo_root_readonly`. Each must still attempt
   its real write (or, for the logdir test, still assert the I6 CONFIG
   property — LOG_DIR present in both `denyRead` and `denyWrite` of
   `.claude/settings.stanok.json`) and assert the expected secure outcome.
   Do NOT weaken any assertion and do NOT convert a config assertion back
   into a self-writability probe.
3. The file must have NO side effect that writes outside `tests/` (no docs/
   write, no file creation anywhere). The `_attempt_write` helper may stay
   (its probe files are created and immediately deleted, which is the
   intended non-destructive probe behavior).

## Requirements

- Pure stdlib only (os, json, pytest as needed).
- No new files. No changes to any other file.
- The four tests must still pass under the sandbox (each asserts a write is
  refused / the config holds).

## Acceptance criteria

- `bash scripts/run.sh test tests/test_adversarial_test.py` passes with all
  four tests green and NO teardown error, in a run where `docs/` is
  read-only (i.e. this ticket, which declares only the test file).
- `tests/test_adversarial_test.py` contains no `autouse` fixture and no code
  that opens `docs/` (or any path outside `tests/`) for writing.
- The full suite (`bash scripts/run.sh test --all`) is green.
