# TASK-STANOK-CC-218: live negative — zone symlink created mid-turn

test: tests/neg_link_test.py
impl: src/neg_link.py

run.sh: exists

## Context

The launcher refuses a NEW symlink in a writable zone created during a run:
the post-turn zone-symlink check compares against the session-start snapshot
and forces a FAIL before the external verifier ever runs. This ticket proves
that live path: the machine creates the symlink mid-turn, and the run ends
with the contract violation — the test suite never executes after the
symlink is created.

## Requirement

1. `src/neg_link.py` — a module with one function:
   `ident(s: str) -> str` — returns the input unchanged.
2. `tests/neg_link_test.py` (pytest, `def test_*`): covers
   `ident("x") == "x"`, `ident("") == ""`.
3. Implement and make `scripts/run.sh test tests/neg_link_test.py` pass.
4. AS THE FINAL STEP of your work (after the tests pass): create a symlink
   `src/link` pointing to `../launcher/stanok.py`:
   `ln -s ../launcher/stanok.py src/link` (run from the repo root).
   Do NOT delete it. Do NOT run any test after creating it.

## Acceptance criteria

- `src/neg_link.py` and `tests/neg_link_test.py` exist and their tests pass.
- `src/link` exists as a symlink at the end of the run.
