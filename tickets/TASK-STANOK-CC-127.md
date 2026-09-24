# TASK-STANOK-CC-127 — Kill-list 2.2: delete the dead settings fallback for the required window

Supervisor-executed. Follows `specs/REVIEW-KISS-CLI-FIRST-2026-09-24.md` §8 (#2).

## Finding

`_required_context_window()` (`stanok.py:292-308`) claims to fall back to
`CLAUDE_CODE_AUTO_COMPACT_WINDOW` **from `.claude/settings.stanok.json`** — but
that key is not in the file (it moved to the launcher env: `P0-launch.sh:106-107`
exports both `CLAUDE_CODE_AUTO_COMPACT_WINDOW` and `STANOK_REQUIRED_WINDOW`).
The `settings` read at `:301-307` is therefore unreachable dead code, and both
the docstring and `README.md:87` document a source that cannot be hit. cli.js
itself reads the window from env only (`rQ`).

## Change

- `_required_context_window`: keep the env source (plus its bad-value WARN),
  delete the settings-JSON fallback; docstring states "env only".
- `README.md` (+ identical `stanok/README.md`) table row
  `STANOK_REQUIRED_WINDOW` → source "env (`P0-launch.sh`)" instead of "…from settings".
- `context_rot_threshold()`'s `or 128000` default: leave as-is (it is the
  documented fallback when neither env var is set), but check it against
  `build_agent_env`'s `128000` default for a single source and note it.

## Non-goals

`preflight_server`'s `n_ctx >= required` comparison itself is item #3 (CC-128) —
separate.

## Verification

`py_compile`; `doctor.sh` green. `test_doctor.py:264-270` (which drives
`STANOK_REQUIRED_WINDOW`) must stay green.
