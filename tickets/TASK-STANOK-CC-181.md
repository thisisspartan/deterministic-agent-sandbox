# TASK-STANOK-CC-181: smoke sequence utilities

impl: src/smoke_seq.py
test: tests/smoke_seq_test.py
run.sh: exists

## Task

Implement small sequence utilities in `src/smoke_seq.py`
(pure stdlib, no third-party imports) and cover them with pytest in
`tests/smoke_seq_test.py`.

Functions:

1. `fib(n) -> int` — the n-th Fibonacci number, `fib(0) == 0`,
   `fib(1) == 1`, iterative (no recursion). `fib(10) == 55`.
   Raises `ValueError` for negative `n`.
2. `is_monotonic(xs) -> bool` — True iff the list is non-decreasing
   (`xs[i] <= xs[i+1]` for all i). Empty and single-element lists are
   monotonic. `is_monotonic([1, 1, 2, 3]) is True`,
   `is_monotonic([3, 1, 2]) is False`.
3. `run_length_encode(xs) -> list` — run-length encoding as a list of
   `[value, count]` pairs in first-occurrence order.
   `run_length_encode([1, 1, 2, 3, 3, 3]) == [[1, 2], [2, 1], [3, 3]]`.
   Empty input → `[]`.

## Requirements

- No network, no files, no global state.
- Inputs are not mutated (the original list order and contents are preserved).
- `fib` is total for all `n >= 0`; `is_monotonic` and `run_length_encode`
  are total for any list of comparable elements.

## Acceptance criteria

- `bash scripts/run.sh test` passes with the new tests green.
- `tests/smoke_seq_test.py` covers: fib (n=0, n=1, known values up to n=10,
  a larger value such as fib(50), negative n raises ValueError),
  is_monotonic (strictly increasing, equal neighbours allowed, decreasing
  pair → False, empty list, single element, unsorted), and
  run_length_encode (the example above, all-distinct input, all-equal input,
  empty input, and that the input list is not mutated by any function).
