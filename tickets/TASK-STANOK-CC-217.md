# TASK-STANOK-CC-217 — verdict integrity: fresh-check authority, contract→FAIL, symlink ban

edit: launcher
impl: launcher/tests_harness/test_verdict_fresh.py
impl: launcher/tests_harness/test_fresh_lifecycle.py

run.sh: exists

## Working zone (explicit override of CLAUDE.md rule 1)

This ticket (operator decision, 2026-10-09) extends your working zone to `launcher/` and
`launcher/tests_harness/` ONLY. Everything else stays forbidden and is physically read-only:
`tests/`, `scripts/` (incl. `scripts/run.sh`, `scripts/stacks/`), `src/`, `docs/`,
`CLAUDE.md`, `.claude/`. Do not attempt to write there; do not create files outside
`launcher/`.

## Task (TDD: red tests FIRST)

Step 1 — write the new tests first, run them, confirm they FAIL (red phase), then implement.

Step 2 — implement the following in `launcher/` (the spec: SPEC-VERDICT-INTEGRITY-2026-10-08,
requirements inlined here; the machine sees only this ticket):

1. **Container lifecycle without `--rm`** (`sandbox.py`, `cli.py`): `docker run` argv drops
   `--rm`. After the run: `docker wait <name>` (its rc becomes `container_rc`), then
   `docker cp <name>:<LOG_DIR>/<label> <LOG_DIR>/<label>` on the host, then `docker rm <name>`.
   Before any `docker run`, remove a leftover container with the same name (`docker rm --force`,
   best-effort). A failed `docker cp` is an INFRASTRUCTURE failure: rc=16, not a verdict.
2. **No rw mount of the log dir** (`sandbox.py`): remove the `log_dir:log_dir:rw` mount. The
   in-container launcher keeps writing verdict files to `LOG_DIR/<label>` inside the container
   (unmounted, container-internal); the host retrieves them via `docker cp` (point 1).
3. **Fresh-check as the verdict authority** (`cli.py`): after the main container exits and its
   files are copied, start a FRESH verification container from the final tree (repo `:ro`,
   no claude process, no nested sandbox): run `bash scripts/run.sh list` and
   `bash scripts/run.sh test --all`; the fresh container's rc is the authority for the final
   `rc`/`verifier`. If the fresh container cannot start or its files cannot be retrieved:
   rc=16 (ENV-FAIL extension — see point 7).
4. **Summary fields and probe priority** (`summary.py`): add `worker_rc` and `worker_verifier`
   (the worker's own claim — diagnostic only, never authoritative). Final `rc`/`verifier`/
   `probe_result` come only from the fresh-check. New probe_results, priority
   **CONTRACT-FAIL > FRESH-FAIL > INTEGRITY-FAIL > session override (NO-OP-PASS/LOOP-TRAP) >
   derived table**: FRESH-FAIL when the fresh rc != 0 or the fresh verifier says FAIL (even
   when the worker claimed PASS or NO-OP-PASS); `worker_rc`/`worker_verifier` keep the worker's
   values unchanged.
5. **Host-side contract recomputation** (`cli.py`): BEFORE the container starts, snapshot
   `{rel_path: sha256}` of the protected files (`tests/**`, `scripts/run.sh`,
   `scripts/stacks/*.toml`) on the host — reuse `launcher.verify._tests_manifest`. AFTER the
   container exits, diff the snapshot against the final tree. A non-empty diff →
   `probe_result="CONTRACT-FAIL"`, `verifier="FAIL"`, regardless of the fresh-check result
   (a fresh run over a tampered tree is not informative). The in-container
   `_contract_lock_forced_fail` stays as the first echelon; the host recomputation is the second.
6. **Post-turn gates in the container** (`session.py`, `gates.py`): after EVERY turn run
   `gates.check_test_config` (already exists, currently launch-only) AND a new symlink scan:
   any symlink (file OR directory, detected via `lstat`) under `tests/`, `src/`, `docs/` or
   `scripts/` → forced fail of the run (reason recorded in `failures`). Do NOT change
   `hidden_files_gate`; do NOT change `scripts/run.sh` or W12.
7. **`exitcodes.py`**: document rc=16 = ENV-FAIL, extended to "fresh-container infrastructure
   failure" (operator decision 2026-10-09).

## Tests (red first)

- `launcher/tests_harness/test_verdict_fresh.py` (NEW): decision-table cases — CONTRACT-FAIL
  overrides everything incl. NO-OP-PASS; FRESH-FAIL overrides CLEAN-FIRST,
  PASS-AFTER-LOCAL-RETRY and NO-OP-PASS; `worker_rc`/`worker_verifier` preserved in the
  summary; INTEGRITY-FAIL does not override CONTRACT-FAIL/FRESH-FAIL.
- `launcher/tests_harness/test_fresh_lifecycle.py` (NEW): with mocked subprocess — argv has
  NO `--rm`; the sequence is run → wait → cp → rm; `docker cp` failure → rc=16 (not a
  verdict); leftover-name cleanup uses `docker rm --force` before run.
- Extend `launcher/tests_harness/test_check_test_config.py`: mid-run `conftest.py`,
  `pytest.ini`, `tox.ini`, `setup.cfg`, `pyproject.toml` under `tests/` are flagged; symlink
  to a file and symlink to a directory under each of the four zones are flagged by the new
  symlink scan.

Run tests with `python -m pytest launcher/tests_harness/<file> -q` from the repo root (a
`conftest.py` for imports already exists there). This container has NO docker binary: tests
that need docker fail with "docker: command not found" — that is an environment limitation,
list them separately in your final report, do not try to fix them. Every other harness test
must pass, including the existing `test_verdict_table.py` and `test_verdict_safety.py`.

## Constraints

- `launcher/tests_harness/test_verdict_table.py` must remain BYTE-IDENTICAL (verified by
  sha256 after the run). New table cases only in `test_verdict_fresh.py`.
- Do not change any existing rc semantics except rc=16 (point 7). Do not touch
  `.claude/settings.stanok.json` (allowedDomains, sandbox.enabled are operator decisions).
- No git writes, no commits.

## Final report (STRICTLY ≤ 8 lines)

1. TASK: DONE / PARTIAL / BLOCKED
2. Files changed (list)
3. Red phase: which new tests failed before implementation
4. Harness: passed N / failed M (docker-env failures listed separately)
