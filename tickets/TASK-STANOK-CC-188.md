# TASK-STANOK-CC-188: smoke interval merge

impl: src/smoke_intervals.py
test: tests/smoke_intervals_test.py
run.sh: exists

## Task

Implement a small, pure interval-merge utility in `src/smoke_intervals.py`
(pure stdlib, no third-party imports) and cover it with pytest in
`tests/smoke_intervals_test.py`.

An interval is a tuple `(start, end)` of integers with `start <= end`,
half-open semantics: it covers the integer points `start, start+1, …, end-1`.

Functions:

1. `merge_intervals(intervals: list[tuple[int, int]]) -> list[tuple[int, int]]`
   — merge overlapping OR touching intervals and return the result sorted
   by start. Two intervals touch when one's `end` equals the other's
   `start` (e.g. `(1, 3)` and `(3, 5)` merge to `(1, 5)`). Nested
   intervals are absorbed: `(1, 10)` and `(2, 3)` merge to `(1, 10)`.
   The input list is NOT mutated. Empty input returns `[]`.
   `merge_intervals([(1, 3), (2, 5), (7, 8)]) == [(1, 5), (7, 8)]`
   `merge_intervals([(1, 3), (3, 5)]) == [(1, 5)]`
   `merge_intervals([(1, 10), (2, 3)]) == [(1, 10)]`
   `merge_intervals([]) == []`
   `merge_intervals([(5, 6)]) == [(5, 6)]`
   `merge_intervals([(2, 3), (1, 2)]) == [(1, 3)]` (unsorted input)
2. `total_length(intervals: list[tuple[int, int]]) -> int`
   — total number of integer points covered after merging.
   `total_length([(1, 3), (2, 5), (7, 8)]) == 5` (points 1,2,3,4 + 7)
   `total_length([]) == 0`
   `total_length([(1, 1)]) == 0` (degenerate interval covers no points)
3. `point_coverage(intervals: list[tuple[int, int]], point: int) -> int`
   — how many DISTINCT merged intervals contain `point`
   (a point is contained in `(s, e)` when `s <= point < e`).
   `point_coverage([(1, 3), (2, 5), (7, 8)], 2) == 1` (merged to one)
   `point_coverage([(1, 3), (7, 8)], 5) == 0`
   `point_coverage([(1, 3), (7, 8)], 1) == 1`
   `point_coverage([], 0) == 0`

## Requirements

- No network, no files, no global state.
- All functions are pure; no mutation of inputs.
- Negative coordinates are valid (e.g. `(-5, -2)`).
- Degenerate intervals (`start == end`) cover no points but must not
  break merging of their neighbours: `merge_intervals([(1, 2), (2, 4)]) == [(1, 4)]`.

## Acceptance criteria

- `bash scripts/run.sh test` passes with the new tests green.
- `tests/smoke_intervals_test.py` covers:
  - `merge_intervals`: all six vectors above; unsorted input; a chain of
    touching intervals `[(0,1),(1,2),(2,3)] == [(0,3)]`; fully disjoint
    input is returned sorted unchanged; the input list is not mutated
    (compare a deep copy before/after); negative coordinates
    `merge_intervals([(-5, -2), (-3, 0)]) == [(-5, 0)]`.
  - `total_length`: the three vectors above; double-counting guard
    `total_length([(1, 5), (1, 5)]) == 4` (not 8).
  - `point_coverage`: the four vectors above; boundary points
    `point_coverage([(1, 3)], 1) == 1` and `point_coverage([(1, 3)], 3) == 0`
    (half-open: end is exclusive).
