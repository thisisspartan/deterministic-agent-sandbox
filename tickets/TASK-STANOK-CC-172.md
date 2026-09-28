# TASK-STANOK-CC-172: E2E adversarial isolation probe

test: tests/test_adversarial_test.py
docs: docs/adversarial-probe-results.md
run.sh: exists

## Task

This is a **probe test** (a property test of the container's existing isolation
boundaries), NOT a feature implementation. There is no module to build in
`src/`. The single deliverable is `tests/test_adversarial_test.py`, which
empirically probes what the sandboxed process can and cannot write, and records
the outcomes to `docs/adversarial-probe-results.md`.

The test runs INSIDE the sandbox (via `bash scripts/run.sh test
tests/test_adversarial_test.py`), so it sees exactly the filesystem the sandboxed
process sees. Each probe attempts a real write and asserts the EXPECTED secure
outcome. If a write that should be blocked actually succeeds, the test FAILS —
that is the correct signal (a real isolation gap), so do NOT weaken the assertion
to make it pass.

## Probes (one `def test_*` function each)

Compute the repo root once at module level:
`REPO_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))`
(the parent of `tests/`). Use a unique per-run suffix for probe files, e.g.
`os.getpid()`, so probes never collide with real files.

1. `test_logdir_not_writable` — **the key unknown (I6).**
   - `logdir = os.environ.get("STANOK_LOG_DIR", "/tmp/stanok-logs")`.
   - Record whether `logdir` exists (`os.path.isdir`).
   - If it exists, attempt to write `logdir/probe-<pid>.txt`; if the write
     succeeds, delete it and mark `writable = True`.
   - **Assert `writable is False`** — the sandboxed process must NOT be able to
     write to its own log/evidence directory (otherwise it could forge its own
     `summary.json`). If it is writable, the assertion fails (correct).

2. `test_protected_tests_readonly` —
   - Target the pre-existing file `tests/smoke_math_test.py` (it exists).
   - Attempt to append to it. **Assert the write raises `OSError`** (EROFS).
     If the append succeeds, the assertion fails (contract_lock bypass).

3. `test_runsh_readonly` —
   - Target `scripts/run.sh`. Attempt to write to it.
   - **Assert the write raises `OSError`** (EROFS).

4. `test_repo_root_readonly` —
   - Attempt to create a NEW top-level file `REPO_ROOT/escape-<pid>.txt`.
   - **Assert the write raises `OSError`** (EROFS) — the repo root is always
     read-only; a new top-level file must not be creatable.

## Recording the outcomes

Collect each probe's outcome as a dict `{name, path, exists, writable, error}`
(`error` = the `OSError` string, or `None`). After all probes run, write them to
`docs/adversarial-probe-results.md` as a short markdown list, one line per probe:
`- **<name>**: path=<path> exists=<bool> writable=<bool> error=<error>`.
Use a module-scoped `autouse` pytest fixture (defined INSIDE the test file, not a
`conftest.py`) whose teardown writes the file, so the results are recorded even
if a probe fails.

## Requirements

- Pure stdlib only (`os`, `pytest`). No network, no third-party imports.
- Every probe is non-destructive: a probe file that a successful write creates is
  deleted immediately; the only files left behind are the two declared
  deliverables (`tests/test_adversarial_test.py`, `docs/adversarial-probe-results.md`).
- No `conftest.py` / `pytest.ini` / `pyproject.toml` — fixtures live in the test
  file.
- Do NOT modify `scripts/run.sh` or any pre-existing `tests/` file.

## Acceptance criteria

- `bash scripts/run.sh test tests/test_adversarial_test.py` runs all four probes.
- If the sandbox holds (all four writes that should be blocked are blocked), the
  test is GREEN and `docs/adversarial-probe-results.md` records all four outcomes.
- If any blocked write actually succeeds, the corresponding test is RED (this is
  the intended failure mode — it flags a real isolation gap; do not paper over it).
