# TASK-STANOK-CC-206: launcher invariant — `edit:` on a protected file is refused (rc=13)

Executor: **supervisor** (supervisor-executed ticket — `launcher/` is outside
the machine's writable zones; no machine launch, no manifest header).
TDD: RED harness tests land BEFORE the fix (the red phase is confirmed by real
test-failure output, not by an exit code alone).

## Incident (the required citation — CC-204-retry3, evidence/ + REVIEW §2)

The ticket declared `edit: tests/smoke_math_test.py`. `host_ro_paths`
(`launcher/stanok.py:702-704`, `if rel in declared_set: continue`) voluntarily
dropped the file from the :ro bind → the machine edited a reference test (1
Edit, turn 1) → the isolation probe `test_protected_tests_readonly` failed →
the run deadlocked in a 31-Read loop (1584 s, `prefix_break: true`) and died
on `ECONNREFUSED`. The ticket created an unsatisfiable contract; the model is
not at fault.

## Change 1 — the gate (fail closed BEFORE any container start)

New function in `launcher/stanok.py`, next to `assert_create_paths_are_new`:

```
def assert_edit_paths_are_not_protected(edit_paths: list[str]) -> None:
```

For every `edit:` path that is in `_protected_files()` (pre-existing
`tests/**` or `scripts/run.sh`) → `ValueError` naming the path and the fix:
a pre-existing test/entrypoint is immutable to the machine; edit it host-side
before launch, or point the ticket at `src/`. Called from `cmd_run` inside the
EXISTING validation try-block (`stanok.py:1758-1772`) right after
`assert_create_paths_are_new` → same `rc=13` path, before `SessionPlan`,
before `preflight_server`, before `sandbox_argv`/`docker run`.

Semantics that MUST NOT change:
- `edit: scripts/run.sh` when run.sh is ABSENT stays legal (bootstrap —
  pinned by `test_edit_path_that_is_absent_is_not_a_defect`; an absent file is
  not in `_protected_files()`).
- `edit:` on an existing NON-protected path (e.g. `src/mod.py`) stays legal.
- `test: tests/new_test.py` (new tests) stays creatable — the rw carve-out +
  per-file :ro overlay are untouched (TDD preserved).
- `parse_ticket_header` stays a pure parser (the gate is a separate function,
  exactly like CC-133's `assert_create_paths_are_new`) — `test_t4_mounts.py`
  and the header-parsing tests are NOT touched.

## Change 2 — remove the loophole

In `host_ro_paths` (`stanok.py:700-704`): delete `declared_set` and
`if rel in declared_set: continue`. Every protected file under a carve-out is
ALWAYS :ro-bound. Rewrite the docstring's "Two exclusions" paragraph: one
exclusion remains (a file outside every carve-out needs no bind — the repo :ro
mount covers it); state the new invariant (`edit:` on a protected path is
refused by the gate before the container starts, so a declared path is never
protected).

## Change 3 — docstrings/messages that would otherwise lie

- `parse_ticket_header` docstring (`stanok.py:731-733`): `edit:` is no longer
  "typically an existing test" — `edit:` on `tests/**` or an existing
  `scripts/run.sh` is refused (rc=13).
- `assert_create_paths_are_new` error message (`stanok.py:793-797`): when the
  stale create-declared path is PROTECTED, do not suggest `edit: <path>` (it
  would now hit the new gate) — say: remove the stale artifact or edit it
  host-side before launch. Keep the `edit:` suggestion for non-protected paths.

## Change 4 — supervisor pre-check

`CLAUDE.supervisor.md` §2 step 3 (the manifest pre-check) gains: `edit:` on a
path from `_protected_files()` (pre-existing `tests/**` or `scripts/run.sh`) →
reject the ticket before launch; editing an existing test is an operator
host-side action.

## Tests (RED first, in `launcher/tests_harness/`)

`test_session_plan.py`:
- NEW `test_edit_on_existing_test_is_a_defect`: existing `tests/old_test.py`,
  header `edit: tests/old_test.py` → `ValueError` naming the path.
- NEW `test_edit_on_existing_runsh_is_a_defect`: existing `scripts/run.sh`,
  header `edit: scripts/run.sh` → `ValueError`.
- NEW `test_edit_on_existing_src_file_is_legal`: existing `src/mod.py`,
  header `edit: src/mod.py` → no raise.
- UPDATE `test_create_paths_that_are_new_pass` (248-256): its
  `edit: tests/old_test.py` on an existing protected test now raises — swap it
  to a non-protected edit (`edit: src/old.py`, existing) so the CC-133 pin
  stays green under the new invariant.

`test_ro_protected_files.py`:
- docstring line 15: replace the "`edit:`-declared files stay writable" bullet
  with the new invariant (all protected files are always :ro; `edit:` on them
  is refused by the gate).
- REPLACE `test_declared_edit_path_is_not_bound` (92-104) with
  `test_declared_protected_path_is_still_bound`: `host_ro_paths` binds a
  protected file even when it appears in the declared list (the loophole is
  gone).
- `test_protected_files_under_a_dir_carve_out_are_bound` (84-89): the
  "either declared or :ro-bound" comment/assert becomes unconditional — every
  protected file under a carve-out is in `ro`.

Hardlink/symlink residual regression (`test_ro_protected_files.py`, docker e2e
pattern already in the file):
- NEW `test_hardlink_escapes_ro_bind_contract_lock_detects`: with
  `rw=("tests",) ro=("tests/old_test.py",)`, inside the container
  `ln tests/old_test.py tests/hard.py && echo x >> tests/hard.py` SUCCEEDS
  (a :ro bind makes the mount point read-only, not the inode — prevention is
  impossible without a directory-bind, which kills TDD) while
  `ln -s tests/old_test.py tests/sym.py && echo x >> tests/sym.py` is DENIED
  (open() follows the symlink to the :ro mount → EROFS). Host-side: the
  changed content is detected — `_tests_manifest` before/after →
  `_check_contract_lock` records `MODIFIED: tests/old_test.py` →
  `_contract_lock_forced_fail` returns rc=1. Detection closes what prevention
  cannot.
- Do NOT add prevention (no directory :ro, no link-count gate) — §7
  primitive-first: the detection primitive already exists.

## Non-goals

`sandbox.py` untouched; `_check_contract_lock`/`_contract_lock_forced_fail`
semantics untouched; no new rc codes (13 is the existing ticket-defect code);
no machine launch.

## Acceptance

1. RED first: the new gate tests fail against the current `stanok.py`
   (real assertion failures, no sandbox errors in the Bash output).
2. After the fix: `pytest launcher/tests_harness` fully green, including the
   docker e2e.
3. `grep -n "declared_set" launcher/stanok.py` → no hits in `host_ro_paths`.
4. `CLAUDE.supervisor.md` §2 carries the pre-check rule.
5. Submodule commit + parent gitlink bump; STATUS.md/CONTEXT.md entries.
