# TASK-STANOK-CC-219: seq.next_after — with a shared test helper module

test: tests/seq_test.py
impl: src/seq.py

run.sh: exists

## Requirement

`src/seq.py` — a module with one function:

`next_after(sorted_nums: list, x) -> int | None` — given a sorted list of
integers, return the smallest element strictly greater than `x`; `None` if
there is none.

## Structure requirement

Put the shared assertion helper used by the test file in a separate module
`tests/helpers.py`:

`assert_next(nums, x, expected)` — calls `next_after` and asserts the result
equals `expected` (raise AssertionError with a clear message otherwise).
`tests/seq_test.py` imports it (`from helpers import assert_next`) and uses
it in every test case. Do not duplicate the helper logic inside the test
file.

## Acceptance criteria

- `tests/seq_test.py` (pytest, `def test_*`) covers: middle element, x below
  all elements, x above all elements -> None, x equal to an element (strictly
  greater), empty list -> None.
- `scripts/run.sh test tests/seq_test.py` -> rc=0 after the implementation;
  `scripts/run.sh test --all` -> rc=0.
