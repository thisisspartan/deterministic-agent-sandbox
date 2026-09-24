# TASK-STANOK-CC-125 — Kill-list 2.A: split `edit:` (modify-in-place) from `test:`

Supervisor-executed. Follows `specs/REVIEW-KISS-CLI-FIRST-2026-09-24.md` §8.A.

## Finding

`prepare_workspace` quarantines **every** declared path (`stanok.py:514`): any
path in the ticket header is treated as "will be created from scratch". For a
ticket that *changes* a pre-existing test (cc119: the 16-color semantics change,
so `tests/fire_color16_test.py` must be edited) this is wrong: the file is moved
aside, then `contract_lock` protects it (the manifest is snapshotted AFTER
quarantine, so the recreated file is unprotected) — and the machine is told to
`git show HEAD:<path>` and recreate it verbatim.

Trace (`cc119-fire16/launcher.stdout.log`): declared without that path →
`CONTRACT-LOCK DENY` ×2 → 1534 s / 62463 output tokens → rc=143. `-retry1`:
same → 1800 s silent stall. `-retry2`: path added to the header → PASS in 276.7 s.
One header line is the whole difference.

## Change

- Ticket header gains `edit: <path>` beside `impl:`/`test:`/`docs:`
  (`_FILE_LINE_RE`).
- `parse_ticket_header` returns `(declared_paths, edit_paths, reset_none)`;
  `declared_paths` stays the union (so `verify_gate`'s positive contract and
  `mutable_paths` are unchanged).
- `SessionPlan` gains `edit_paths: tuple = ()` (default, so existing test
  constructions keep working).
- `prepare_workspace` quarantines `declared_paths - edit_paths`: a declared
  pre-existing file intended for in-place modification is NOT moved aside.
- `edit:` paths remain in `mutable_paths` → the PreToolUse hook allows the edit
  and `_check_contract_lock` exempts it (both already keyed on `mutable_paths`).
- `cmd_run`: log the two lists distinctly.

The non-negotiable invariant is untouched: *undeclared* pre-existing tests stay
protected. Only the "recreate verbatim" crutch disappears.

## Verification

New tests in `test_session_plan.py` / a header-parse test: `edit:` path present in
`declared_paths` but absent from the quarantine set; still mutable. `py_compile`;
`doctor.sh` green.
