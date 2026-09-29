# TASK-STANOK-CC-180: smoke statistics utilities

impl: src/smoke_stats.py
test: tests/smoke_stats_test.py
run.sh: exists

## Task

Implement small descriptive-statistics utilities in `src/smoke_stats.py`
(pure stdlib, no third-party imports) and cover them with pytest in
`tests/smoke_stats_test.py`.

All functions take a non-empty list of numbers (`xs`).

Functions:

1. `mean(xs) -> float` — arithmetic mean. `mean([1, 2, 3, 4]) == 2.5`.
2. `median(xs) -> float` — median; for an even count, the mean of the two
   middle values of the sorted input. `median([3, 1, 2]) == 2.0`,
   `median([4, 1, 3, 2]) == 2.5`.
3. `variance(xs) -> float` — population variance
   (`sum((x - mean)^2) / n`, never negative). `variance([1, 2, 3, 4]) == 1.25`.

## Requirements

- No network, no files, no global state.
- Inputs are not mutated (the original list order is preserved).
- All functions are total for any non-empty list of ints or floats.

## Acceptance criteria

- `bash scripts/run.sh test` passes with the new tests green.
- `tests/smoke_stats_test.py` covers: mean (int list, float list, single
  element, negative values), median (odd count, even count, unsorted input,
  duplicates, single element), variance (known value 1.25 for [1,2,3,4],
  constant list → 0.0, single element → 0.0, float values), and that the
  input list is not mutated by any of the three functions.
