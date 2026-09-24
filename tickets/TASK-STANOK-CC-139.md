# TASK-STANOK-CC-139 — `hidden_files_gate` walks recursively

Supervisor-executed (`launcher/` is RO in the container). This is the first
**Appendix A** item of `specs/AUDIT-STANOK-2026-09-24.md` (#3), taken after the
§4 ACTION PLAN closed at CC-138; approved by the operator as CC-139.

## Finding

`hidden_files_gate` (the W4 hygiene gate, rc=26) read each writable zone with
`os.listdir` and `if not os.path.isfile(path): continue` — one level only. So a
leftover in a subdirectory survived the gate: the audit's Appendix A #3
("`hidden_files_gate` reads only the top level of each zone … a hidden file in
`src/pkg/` is invisible").

Confirmed empirically before the change (patched `REPO_ROOT`, temp tree):
`src/pkg/.secret` → gate **False** (missed); adding `src/.secret2` at the top
level → **True**. Both signals (hidden name, `TEMP:` marker) were top-level only.

## Change

- `stanok.py`: the `os.listdir` loop becomes an `os.walk` over the same four
  zones (`sandbox.WRITABLE_ZONES`). For every directory entry and every file at
  any depth: a name starting with `.` (except `.gitkeep`) flags the gate.
  - A hidden **directory** is flagged too. It is the same class of leftover, and
    without this a dot-dir holding only non-hidden files
    (`src/.cache/notes.md`) would still leak its name and contents.
  - Fail-closed is preserved and extended to the walk: `os.walk`'s default
    `onerror` silently skips an unreadable directory, so errors are collected
    via `onerror=walk_errors.append` and, if any occurred, the gate flags
    (mirrors the old `listdir`/read `OSError` branches). `followlinks=False`
    (the default) is kept — a symlink is not descended.
- `test_hidden_files_gate.py`: the four existing tests are unchanged in intent;
  the full-path rc=26 test was refactored into `_rc26_launch(tmp_path, rel)` and
  the nested case added. New: nested hidden file, hidden directory, nested
  `TEMP:` marker, and a `main()` launch with a committed nested hidden file →
  rc=26 + `EARLY-ABORT`.

## Verification

- `py_compile` (stanok.py).
- `bash hooks/doctor.sh` — **151 passed, 0 skipped on a clean tree**
  (147 + 4).
- The rc=26 end-to-end test proves the new code path through the real launcher
  binary, not just the predicate.

## Non-goals / residuals

- The gate is still the owner's deliberately narrow pair of signals (hidden
  name / `TEMP:` marker), not "any undeclared file" — recursion changes WHERE it
  looks, not WHAT it looks for.
- Symlinked directories are not descended (`followlinks=False`). The T4
  carve-out validation already refuses a declared path that resolves through a
  symlink, so a symlink under a zone is out of the declaration surface; if that
  changes, this is the hook to revisit.
- The audit's Appendix A text still describes the top-level limitation — it is a
  point-in-time document and was not rewritten. Appendix A items #1, #5 were
  resolved as recon (see CONTEXT); #2 and #4 still need a live model run /
  image probe.
