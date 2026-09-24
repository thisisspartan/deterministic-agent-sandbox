# TASK-STANOK-CC-136 — T4b: the pre-existing contract files are `:ro` at the fs layer

Supervisor-executed (`launcher/` is RO in the container). Follows
`specs/AUDIT-STANOK-2026-09-24.md` §2 (boundary table, row 1) and §4 item 5:
CC-135 shipped the `:rw` half of the native equivalent; this is the `:ro` half
that T5's e2e needs. Split out of the CC-135 numbering by operator decision
(2026-09-24).

## Finding

`declared_carveout` (CC-135) can bind an ABSENT declared path only through its
nearest existing ancestor DIRECTORY — Docker creates a missing bind source as a
root-owned directory, so a per-file bind is impossible. The ordinary TDD ticket
declares a NEW test (`test: tests/new_test.py`), so its carve-out is `tests/`
and **every pre-existing reference test in it becomes writable at the filesystem
layer again**. That is exactly the incident class §2 row 1 describes, and it
made the T5 e2e ("an attempt to rewrite a pre-existing test fails at the fs
layer with a readable error") unachievable: deleting `_pretooluse_lock_hook`
would have left the pre-existing tests protected only by the post-turn
`_check_contract_lock` diff — one wasted turn, then a relaunch.

The audit already names the mechanism: "`:ro` bind of pre-existing test files +
`:rw` bind of declared paths (Docker layers by specificity)".

## Change

- `stanok.py` — `_protected_files()` split out of `_tests_manifest()` as the ONE
  source for "protected": `tests/**` (no `__pycache__`) + `scripts/run.sh`. The
  manifest now hashes that list instead of re-implementing the walk, so the
  hashed set and the mounted set cannot drift.
- `host_ro_paths(declared, rw_paths)`: the protected files that must be re-bound
  `:ro`, i.e. those **under a rw carve-out** (outside one, the repo `:ro` mount
  already covers them), **minus the declared paths** — `edit: tests/x_test.py` is
  an explicit in-place contract and must stay writable.
- `sandbox.py`: `sandbox_argv(..., ro_paths=())` emits
  `-v <repo>/<rel>:<repo>/<rel>:ro` **after** the rw binds (deeper destination
  wins), default `()` = bind nothing.
- `main()` derives both lists from the same parsed ticket and passes them to
  `run_sandboxed(args, rw_paths, ro_paths)` → `sandbox_argv`.

Verified layering (hand probe, image `stanok-machine:latest`): with
`tests/` `:rw` and `tests/old_test.py` `:ro`, `touch tests/new_test.py` succeeds
while `echo x >> tests/old_test.py` is `Read-only file system`.

Two echelons, deliberately: the PreToolUse deny (`_pretooluse_lock_hook`) is
still the first, with a readable reason; the filesystem is now the second for
Bash-mediated writes the hook cannot see. Deleting the first is CC-137 (T5).

## Verification

- `py_compile`.
- New `launcher/tests_harness/test_ro_protected_files.py`, 8 tests:
  `_protected_files` = tests/** + scripts/run.sh (and identical to the manifest's
  key set — one source), no `__pycache__`, a missing `scripts/run.sh` is not
  protected (bootstrap); `host_ro_paths` binds nothing when no protected file is
  under a carve-out, binds all pre-existing tests under a dir carve-out (with
  the coverage property: every protected file under the carve-out is either
  declared or bound), never binds a declared `edit:` path, and binds
  `scripts/run.sh` only when `scripts/` is carved out; the argv carries the
  `:ro` bind after the `:rw` bind (and none by default); and a **real
  `docker run`** through the launcher's own derivation:
  `tests/old_test.py` → `OLD-DENIED`, `tests/new_test.py` → `NEW-OK`, the host
  copy byte-identical (the mount refused the write; it did not redirect it).
- `hooks/doctor.sh` — **150 passed, 0 skipped on a clean tree** (+8; CC-135 =
  142).

## Non-goals / residuals

- **T5 is CC-137**, not this ticket: `_pretooluse_lock_hook` and
  `_check_contract_lock` are untouched. This ticket is T5's precondition, and
  the e2e above is T5's acceptance criterion, proven *before* the deletion.
- "Protected" is deliberately the contract_lock set (`tests/**` +
  `scripts/run.sh`). A pre-existing file in another carved-out zone (`docs/old.md`
  with `docs/` a carve-out) stays writable — docs are not contract files, and
  that was true under the zone-level mounts too.
- A protected file that the ticket also declares is not bound (`edit:` is the
  sanctioned way to modify a reference test in place). A ticket cannot get "rw
  and immutable" at once.
- The bind list grows with the number of test files (one `-v` per protected file
  under a carve-out; ~12 in the stanok repo). Docker handles this; a directory
  with thousands of tests would want a different mechanism (not needed now).
