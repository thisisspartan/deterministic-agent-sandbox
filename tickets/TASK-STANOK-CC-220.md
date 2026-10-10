# TASK-STANOK-CC-220: seq.next_after — implementation delegates to a shared helpers module

test: tests/seq_test.py
impl: src/seq.py

run.sh: exists

## Requirement

`src/seq.py` — a module with one function:

`next_after(sorted_nums: list, x) -> int | None` — given a sorted list of
integers, return the smallest element strictly greater than `x`; `None` if
there is none.

## Structure requirement

`src/seq.py` must NOT implement the search itself: it delegates to a shared
module importable as `helpers` (`from helpers import search`), and the test
file imports `from helpers import assert_next` — `assert_next(nums, x,
expected)` calls `next_after` and asserts the result equals `expected`
(raise AssertionError with a clear message otherwise).

Put the `helpers` module where BOTH the implementation and the tests can
import it. Do not duplicate the helper logic inside `src/seq.py` or inside
the test file.

## Acceptance criteria

- `tests/seq_test.py` (pytest, `def test_*`) covers: middle element, x below
  all elements, x above all elements -> None, x equal to an element (strictly
  greater), empty list -> None.
- `scripts/run.sh test tests/seq_test.py` -> rc=0 after the implementation;
  `scripts/run.sh test --all` -> rc=0.
