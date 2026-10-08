# TASK-STANOK-CC-213 — smoke_wt: live worktree-run probe

impl: src/smoke_wt.py
test: tests/smoke_wt_test.py

run.sh: exists

## Task

Create `src/smoke_wt.py` with a function `wt_probe()` that returns the string
`"worktree-ok"`, and `tests/smoke_wt_test.py` with `test_wt_probe()` asserting
`wt_probe() == "worktree-ok"`.

## Constraints

- No other files; no extra dependencies.
- Do not touch `scripts/run.sh` or any existing test.
