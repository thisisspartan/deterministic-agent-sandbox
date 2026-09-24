# TASK-STANOK-CC-121 — Kill-list 3.1: drop the cli.js path-resolver mirror

Supervisor-executed (launcher/ is RO in the container). Follows
`specs/REVIEW-KISS-CLI-FIRST-2026-09-24.md` §3.1 (T2 was Option B here; it was later burned
in full — CC-131 / REVIEW §9).

## Finding

`sandbox_config_gate` guarded CC-107 (a bogus `sandbox.filesystem` deny entry →
bwrap EROFS on every Bash call), which is worth keeping. But it did so via
`_resolve_sandbox_path`, a Python **reimplementation of cli.js's resolver**
(`//X`, `~`, absolute, settings-relative; comment: "Mirror cli.js Rn6/lq", "V_6").
That is the exact crutch class that produced CC-075: a hand-rolled model of native
path semantics that can silently diverge from cli.js.

## Change

- Delete `_resolve_sandbox_path`.
- `sandbox_config_gate` now constrains the config instead of modelling cli.js:
  entries must be settings-relative (`../<name>`) or absolute; `~`/`//` are
  **rejected** as unsupported. Existence is checked directly
  (`entry` if absolute else `normpath(base/entry)`).
- Tests: add `test_tilde_entry_rejected` (8 total in the file).

Behavior for the shipped config (all `../*`) is unchanged. `doctor.sh` green
(113 passed, 2 skipped).

## Non-goals

`preflight_image`/`_stack_preflights` (3.2), `_extract_smart_diff` (3.3),
README §139-393 (3.4) — separate tickets.
