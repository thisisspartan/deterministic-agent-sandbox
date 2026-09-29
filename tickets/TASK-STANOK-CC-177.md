# TASK-STANOK-CC-177: clamp helper (AUDIT #2 tool-availability probe)

impl: src/audit_probe2.py
test: tests/audit_probe2_test.py
run.sh: exists

## Task

Implement `clamp(value, lo, hi)` in `src/audit_probe2.py`:

- Return `lo` when `value < lo`.
- Return `hi` when `value > hi`.
- Return `value` unchanged when `lo <= value <= hi`.
- `value`, `lo`, `hi` are `int` or `float`.
- If `lo > hi`, raise `ValueError`.

## Requirements

- Pure stdlib only.
- Exactly one module `src/audit_probe2.py` and one test file
  `tests/audit_probe2_test.py`. No other files, no new dependencies.

## Acceptance criteria

- `bash scripts/run.sh test tests/audit_probe2_test.py` passes.
- The tests cover: below-range, above-range, in-range, the exact
  boundaries (`value == lo`, `value == hi`), and the `lo > hi` ValueError case.
- The full suite (`bash scripts/run.sh test --all`) is green.
