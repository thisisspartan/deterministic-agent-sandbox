# TASK-STANOK-CC-154 — harden the CC-150 bootstrap gate (repo-root rw)

Supervisor-executed (`launcher/` is RO in the container — no machine launch).
Follow-up to the CC-150 review in
`specs/AUDIT-STACK-FLEXIBILITY-2026-09-25.md` / the 2026-09-25 verification
pass. Commit under review: submodule `1a4f1a5`.

## Incident / context

CC-150 added `bootstrap: <path>` for a **new top-level file** (a fresh project's
`pyproject.toml`/`package.json` — `declared_carveout` cannot carve a new
top-level path). Its implementation (`launcher/stanok.py` `main()` bootstrap
branch + `launcher/sandbox.py` `repo_rw`/`repo_mode`) mounts the **repo root
itself rw** and re-binds `:ro` only:

- `.git` (appended in `main()`), and
- the protected files from `host_ro_paths(declared, ("",) + rw_paths)`
  = `tests/**` + `scripts/run.sh` (`_protected_files`).

Everything else under the repo root — `launcher/`, `hooks/`, `.claude/`,
`Dockerfile`, `setup.sh`, `CLAUDE.md`, `docs/`, README — becomes **writable**
during a bootstrap ticket. In the pet repo that is the harness itself: a
bootstrap ticket can persist edits to the launcher/settings that apply to
**future** runs (the running process is in memory, but the bind is to the host
tree).

Second vector: `_validate_bootstrap_path` allows bootstrap when
`scripts/run.sh` is "absent OR declared in this ticket". So a bootstrap ticket
in a repo that already has `run.sh` must also declare `edit: scripts/run.sh`,
which drops `run.sh` from `_protected_files`' ro set → `run.sh` becomes
writable → the exact verdict-subversion surface the contract lock exists to
close.

## Change (choose one; (A) preferred)

- **(A) No repo-root rw.** In `prepare_workspace`, after header validation
  (which still sees the path absent), **pre-create** the bootstrap file on the
  host (mode 0644, empty) and carve it out as a single file rw
  (`declared_carveout` on an existing file returns itself). Delete `repo_rw`
  from `sandbox.sandbox_argv` and the bootstrap branch in `main()`. The base
  repo stays `:ro`; only the one audited file + the four zones are writable.
- **(B) Whitelist instead of blacklist.** If root rw is kept, re-bind `:ro`
  every **pre-existing top-level entry** except the bootstrap path and
  `src/tests/docs/scripts` (not just `.git` + protected files).
- **Both:** reject `bootstrap:` when the ticket also declares
  `edit: scripts/run.sh` (rc=13) — bootstrap must not coexist with a write to
  the entrypoint.

## Verification

- Extend `launcher/tests_harness/test_bootstrap_gate.py`: a bootstrap ticket
  leaves `launcher/`, `hooks/`, `.claude/`, `Dockerfile` unwritable (docker e2e
  `Read-only file system`); `run.sh` unwritable; the bootstrap file writable;
  base repo mount stays `:ro` for (A).
- `bootstrap: pyproject.toml` + `edit: scripts/run.sh` → rc=13.
- `bash hooks/doctor.sh` green (image rebuilt after the change).
- Re-run the CC-148/CC-149-style smoke on the machine once, since the mount
  argv changes.

## Non-goals / residuals

- No change to the normal (non-bootstrap) declared-path path.
- Does not decide whether bootstrap is wanted at all — that is D1 in the plan;
  this ticket only makes the accepted mechanism safe.
