# TASK-STANOK-CC-137 — T5: delete the PreToolUse contract_lock deny hook

Supervisor-executed (`launcher/` is RO in the container). Follows
`specs/AUDIT-STANOK-2026-09-24.md` §4 item 5, and closes the precondition CC-136
declared: the fs layer refuses a pre-existing-test rewrite, so the in-process
deny hook is redundant. Operator decision 2026-09-24: delete it now (the live
smoke comes later, see Non-goals).

## Finding

contract_lock had two echelons:

1. `_pretooluse_lock_hook` — an SDK PreToolUse callback on Edit|Write|MultiEdit
   that compared `tool_input.file_path` against `plan.protected_paths` (a
   snapshot of `_tests_manifest()` keys wired in through `dataclasses.replace`)
   and returned `{"decision": "block"}` for a pre-existing protected file.
2. `_check_contract_lock` — the post-turn SHA256 manifest diff, the fallback for
   Bash-mediated writes the hook cannot see.

Echelon 1 was a Python copy of a rule the kernel can now enforce: CC-136 binds
the same protected list `:ro` over the rw carve-out (Docker layers by
specificity), and its e2e proves `tests/old_test.py` → `OLD-DENIED` while a new
sibling stays creatable. Keeping the hook meant a second policy list in the plan
(`protected_paths`) that only the hook read, kept in sync by hand — exactly the
drift CC-135 removed for `rw_zones`.

## Change

- `stanok.py`:
  - `_pretooluse_lock_hook` + the `_CONTRACT_LOCK_STATE` global deleted.
  - The `"PreToolUse": [HookMatcher(matcher="Edit|Write|MultiEdit", …)]` entry
    removed from the `hooks={…}` dict passed to `ClaudeAgentOptions`; the
    `PostToolUse` verifier hook matcher is untouched.
  - `SessionPlan.protected_paths` deleted (write-only: its sole reader was the
    hook). Fields are now `declared_paths`, `mutable_paths`, `git_mode`,
    `edit_paths`.
  - The finalize block is now just `tests_manifest_before = _tests_manifest()`
    (the diff consumer is unchanged and still fail-closed).
  - Comments updated: contract_lock = mount (`:ro`, CC-136) + post-turn diff;
    `host_ro_paths` now names them first and second echelon.
- `launcher/tests_harness/test_pretooluse_lock.py` deleted (7 tests, all about
  the hook). `test_session_plan.py`: `_build_plan` no longer passes
  `protected_paths`; `test_plan_fields_from_ticket_header` pins the field set to
  exactly those four; the manifest test repurposed to pin the deletion
  (`not hasattr(plan, "protected_paths")`, `not hasattr(stanok,
  "_pretooluse_lock_hook")`). `test_doctor.py`, `test_launcher_preflight.py`,
  `test_verdict_safety.py`: `protected_paths=` removed.
- `README.md` + `CLAUDE.md`: the "two points" sentence now reads `:ro` mount
  (kernel EROFS) + post-turn manifest diff.

## Verification

- `py_compile` (stanok.py, sandbox.py).
- `bash hooks/doctor.sh` — **143 passed, 0 skipped on a clean tree**
  (150 − 7 deleted hook tests; no test was weakened to pass).
- The deletion is licensed by CC-136's real `docker run` e2e
  (`test_pre_existing_test_is_erofs_new_sibling_creatable`: OLD-DENIED +
  NEW-OK, host copy byte-identical), which stays in the suite and runs as part
  of doctor.

## Non-goals / residuals

- **The live smoke has not been run.** No full machine session was executed
  since the deletion (the model's own attempt to Edit a pre-existing test now
  fails with "Read-only file system" from the tool, not a `block` decision from
  a hook). The mechanism is proven at the fs layer by CC-136's e2e; the
  end-to-end wording/UX observation is deferred to the next smoke run.
- The `:ro` bind prevents a MODIFICATION, not a UNLINK (deleting a file is a
  write to the parent dir, which stays rw). Deleting a protected file is
  therefore still possible at the fs layer and is caught by the post-turn diff
  — fail-closed, but one turn later. That is precisely why echelon 2 is kept.
- `_check_contract_lock` and its mutable-path exemption are untouched, so the
  audit's §2 row-1 class (a rewritten reference test) is now refused by the
  kernel and a deleted one still fails the run.
- Historical specs (`HANDOFF-ARCH-REVIEW.md`, the audit itself) still describe
  the hook; they are point-in-time documents and were not rewritten.
