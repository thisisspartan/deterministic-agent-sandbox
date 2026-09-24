# TASK-STANOK-CC-135 — T4: the container's rw mounts are derived from the ticket

Supervisor-executed (`launcher/` is RO in the container). Follows
`specs/AUDIT-STANOK-2026-09-24.md` §4 item 4 (§2 boundary table, §3.2 contract v2,
§1#7 — the last two were folded into this ticket by CC-132's decision).

## Finding

Two policy layers with different granularity (§2, the root cause): the mounts
were **zone-level** (`sandbox.DEFAULT_RW_ZONES` → `src/ tests/ docs/ scripts/
evidence/` rw), while the ticket is **file-level**. That is why every Python
tripwire existed — the mount grants the whole zone, the hook then re-imposes the
file rule in Python. `SessionPlan.rw_zones` was the second policy list and
became write-only the moment CC-134 deleted `DEFAULT_RW_ZONES` (nothing read it:
`run_sandboxed` mounted `sandbox.WRITABLE_ZONES` directly). §1#7: the 4-zone
allowlist rejected every root file and every other top-level dir (`go.mod`,
`Makefile`, `internal/`, `cmd/`) — "any stack" was impossible.

## Change

- `stanok.py` — one rule, `declared_carveout(rel) -> str | None`, returns the rw
  carve-out a declared path implies (or None = undeclarable):
  - relative, no `..`, `realpath` inside the repo (a symlink resolving outside
    is refused — Docker resolves a bind source's realpath, so an in-repo link
    could smuggle an outside dir in; run.sh already refuses symlinked test
    paths, SEC-01);
  - a bare zone name (`src`, `tests/`) → None (quarantine would move the whole
    zone out of the tree);
  - exists (file or dir) → itself: a per-file / per-dir rw bind;
  - absent → its **nearest existing ancestor dir**, which must be BELOW the repo
    root. Docker creates a missing bind SOURCE as a root-owned **directory**
    (verified 2026-09-24), so an absent path cannot be file-bound at all; and
    binding the repo root rw would dissolve the boundary → None.
- `_validate_declared_path` is now exactly `declared_carveout(rel) is not None`
  — the parse gate and the mounts are the same rule, so a ticket cannot be
  accepted whose paths the container has no way to write. The error message
  names the reason (a NEW top-level file/dir has no safe carve-out).
- `SessionPlan.rw_zones` **deleted** (fields: declared_paths, mutable_paths,
  protected_paths, git_mode, edit_paths). I1 holds: the mount set is derived
  from `mutable_paths`, never a second list.
- `host_rw_paths(declared)`: the deduped carve-outs, ticket order. `main()`
  derives them from the same ticket text with the same parser, **before**
  `docker run` (the container builds its own plan only after it starts), so a
  refused header is rc=13 with no container launched. Derivation happens only in
  the sandboxed branch — the in-process (container side / `--direct`) branch is
  byte-for-byte unchanged.
- `sandbox.py`: `sandbox_argv(..., rw_paths: tuple = ())` (was
  `rw_zones=DEFAULT...`); the mounts are emitted per carve-out. The default is
  **fail-closed**: a caller that forgets the carve-outs gets a read-only
  container, not an open one.
- The zone dirs are **no longer manufactured** — neither by `run_sandboxed`
  (host, removed) nor by `prepare_workspace` (container, removed). They were the
  rw mount points; T4's carve-out sources always exist by construction, and
  inside the container a `makedirs` of a non-carved-out zone would now be an
  EROFS error instead of a no-op.
- `sandbox.py` baseline env: `PYTHONDONTWRITEBYTECODE=1` — a declared file
  inside an otherwise-ro dir must not make CPython drop `__pycache__/*.pyc` next
  to it (run.sh's py runner already sets it for pytest; this covers the agent's
  own python invocations).
- README: mount layout, the ticket-validation paragraph, the structure block.

Consequence (§1#7 is now a property of the derivation, not a widened list):
`edit: go.mod` (exists → file bind) and `impl: internal/x.go` (dir exists →
dir bind) are declarable; a NEW top-level `foo.py` is refused. A declared path
under a zone whose dir does not exist (`docs/x.md` with no `docs/`) is now
refused too — the launcher no longer creates zone dirs in the operator's repo
(`mkdir docs` is the fix, and the error says so).

## Verification

- `py_compile` (launcher + harness).
- New `launcher/tests_harness/test_t4_mounts.py`, 11 tests: the rule
  (existing file → itself; existing dir → itself; absent → nearest existing
  ancestor; absent top-level → None; bare zone → None; traversal + symlink
  escape → None), the derivation over a list (`host_rw_paths` dedupes and every
  emitted source exists; every declared path is covered by a carve-out),
  `parse_ticket_header` refusing an undeclarable path, `rw_zones` absent from
  the plan, and a **real `docker run`** through the argv the launcher builds
  (`rw_paths=("src/mod.py", "docs")`):
  `touch src/mod.py` → `FILE-RW-OK`, `touch src/sibling.py` → `SIBLING-DENIED`,
  `touch docs/new.md` → `PARENT-RW-OK`, `touch tests/x.py` → `UNDECLARED-DENIED`.
  That is the audit's e2e (RW on a declared path, EROFS on a non-declared one)
  plus the absent-path/ancestor case, in one container.
- The T3 premise re-verified by hand on the image (`stanok-machine:latest`):
  an existing file bound `:rw` over the `:ro` repo is writable
  (`FILE-RW-OK`), its sibling refused (`SIBLING-DENIED`).
- `hooks/doctor.sh` — **142 passed, 0 skipped on a clean tree** (+11; CC-134 =
  131). The 4 suites that constructed `SessionPlan(..., rw_zones=...)` were
  updated; `test_evidence_boundary.py`'s argv assertions and both hermetic
  `test_session_plan.py` repos now carry the `docs/` dir their sample ticket
  declares (CC-135 consequence, not a test hack: a declared path needs an
  existing carve-out).

## Non-goals / residuals

- **CC-136 (T5)** — delete `_pretooluse_lock_hook` once this is e2e-proven; this
  ticket only moves the mount layer. The PreToolUse deny and `_check_contract_lock`
  are unchanged and still the enforcement while the hook exists.
- **Ancestor-dir residual (inherent to Docker):** a declared ABSENT path gets its
  nearest existing ancestor dir rw — `test: tests/new.py` makes all of `tests/`
  rw, so a sibling pre-existing test is writable at the fs layer. The per-FILE
  guarantee holds only for paths that exist. §2's T5 e2e ("rewrite a pre-existing
  test fails at the fs layer") must therefore be specified as: the *file* case
  fails (sibling EROFS), while the *absent-declared-sibling* case is only caught
  by `_check_contract_lock` — this is why T5 (hook deletion) is gated on a
  design decision, not just on this ticket.
- `edit:` on an absent path stays legal (checked in neither direction, CC-133):
  it is declarable when its ancestor exists, and creates nothing.
- Hidden-file gate still scans only the top level of the zones (audit
  Appendix A #3, unverified/unrequested).
