# TASK-STANOK-CC-133 — Derive create-vs-edit from the filesystem (rc=13)

Supervisor-executed (`launcher/` is RO in the container). Follows
`specs/AUDIT-STANOK-2026-09-24.md` §4 item 2 (evidence §1#5 + the CC-119 traces).

## Finding

`create:`-vs-`edit:` is a header CLAIM that nothing verified. A pre-existing
path declared as a create (`impl:`/`test:`/`docs:`) was silently quarantined
(`prepare_workspace`, 511-536), so the run started against a file the agent
could no longer see — while the ticket text still described the file it had
just removed. The CC-119 fire16 traces show both halves of the damage:

- `cc119-fire16`: the ticket wanted to MODIFY the pre-existing
  `tests/fire_color16_test.py` but did not declare it at all → the hook denied
  the write twice (`CONTRACT-LOCK DENY`, log lines 16-17) → turn 1 burned
  1534 s → `rc=143`.
- `cc119-fire16-retry2`: the header was "fixed" by declaring that same
  pre-existing file as a `test:` (create) → quarantine moved it aside → the
  agent rewrote it from scratch. It PASSed (276 s), but only because the
  quarantine silently removed the file. That is the hidden-magic path the
  native-first/KISS push wants gone: the supervisor's intent was never checked.

## Change

`assert_create_paths_are_new(declared, edit_paths)` in `launcher/stanok.py`,
called in `cmd_run` right after `parse_ticket_header` **inside the existing
try** — a `ValueError` there reuses the rc=13 path, so no new abort block.

- A create-declared path that already exists → `ValueError` naming the path and
  the fix (`declare it as \`edit: <path>\``), fail-closed rc=13, **before any
  workspace mutation** (so nothing is quarantined, no container starts, no
  agent runs, no deny-loop, no 1800 s watchdog).
- `edit:` paths are exempt; genuinely new paths pass.
- Only this direction is checked (see Non-goals).

Deliberate consequence: the retry2 shape (a clean tree containing a
pre-existing file, declared as a create) is now `rc=13`. The equivalent work is
`edit: <path>` — which does NOT quarantine and is exempt from the contract-lock
hook, so the agent may rewrite the file in place. The supervisor/TUI must mark
pre-existing artifacts `edit:`; the failure is now loud and names the fix
instead of degrading into a quarantine+deny loop.

## Verification

- `py_compile`.
- 3 hermetic tests in `test_session_plan.py`:
  `test_stale_create_path_is_a_defect` (the exact retry1 header),
  `test_create_paths_that_are_new_pass`,
  `test_edit_path_that_is_absent_is_not_a_defect`.
- `test_doctor.py::test_runner_stale_create_rc13` — **end to end through
  `main()`** on a private git-init'ed repo: rc=13 with the reason pinned from
  `summary.json` (`already exists` + `edit: tests/fire_color16_test.py`), and
  NOT the "ticket not found" rc=13. Reproduced by hand:

```
$ STANOK_REPO=/tmp/stale-probe/repo STANOK_SERVER_URL=http://127.0.0.1:59999 \
  STANOK_NO_SANDBOX=1 ./launch.sh run /tmp/stale-probe/t.md stale-probe
STANOK RUNNER | Repo: /tmp/stale-probe/repo | Label: stale-probe
RC=13
errors: ["ticket parse error: declared path 'tests/fire_color16_test.py' already
  exists but is declared as a create (impl:/test:/docs:); declare it as
  `edit: tests/fire_color16_test.py` to modify it in place, or remove the
  stale artifact"]
```

- `hooks/doctor.sh` — **123 passed, 2 skipped** (was 119/2; +4). The 2 skips are
  the pre-existing dirty-tree-dependent mock launches (the working tree is dirty
  while this ticket is uncommitted).

## Non-goals

- The second direction of contract v2 (`edit:` on a path that does NOT exist →
  defect) is **not** enforced: it is not destructive (the agent simply creates
  the file), it is not in AUDIT §4, and a bootstrap ticket may legitimately
  declare `edit: scripts/run.sh` before run.sh exists. Separate ticket if a real
  incident appears.
- Retiring `prepare_workspace`'s quarantine loop. It is now unreachable for the
  normal path (a create-declared path is guaranteed absent at parse time), but
  it stays as the non-destructive safety net decided in CC-131 ("quarantine
  stays as-is"); deleting it would be a separate, evidence-backed ticket.
- `edit:`-vs-`ro:` vocabulary, and the create/edit → mount derivation (T4/CC-135).
