# TASK-STANOK-CC-208: smoke sort utilities

impl: src/smoke_sort.py
test: tests/smoke_sort_test.py
run.sh: exists

## Deliverable

`src/smoke_sort.py` — three pure functions (no imports; no randomness).
Inputs are never mutated.

1. `insertion_sort(items) -> list`
   - Stable ascending sort of numbers; empty list -> empty list.
   - Vectors: `[]` -> `[]`; `[3,1,2]` -> `[1,2,3]`; `[5,5,1]` -> `[1,5,5]`;
     `[2,-3,0,-3,2]` -> `[-3,-3,0,2,2]`; `[1]` -> `[1]`.

2. `merge_intervals(intervals) -> list`
   - Input: list of `(start, end)` tuples with `start <= end`; output: sorted
     by `start`, overlapping OR touching intervals merged into one.
   - Vectors: `[]` -> `[]`; `[(1,3),(2,4)]` -> `[(1,4)]`;
     `[(1,2),(3,4)]` -> `[(1,2),(3,4)]`; `[(1,4),(4,5)]` -> `[(1,5)]`;
     `[(5,6),(1,2),(1,5)]` -> `[(1,6)]`; `[(2,2),(1,1)]` -> `[(1,1),(2,2)]`.

3. `mode(values) -> int | str | None`
   - Most frequent element; on a tie the smallest value wins (numeric
     comparison for numbers; the input is homogeneous); empty -> None.
   - Vectors: `[]` -> None; `[1,2,2,3]` -> 2; `[1,1,2,2]` -> 1;
     `[7]` -> 7; `["b","a","b","a"]` -> "a"; `[3,3,2,2,1]` -> 2.

## Acceptance

- `bash scripts/run.sh test --all` exits 0 (all tests green).
- `tests/smoke_sort_test.py` covers every vector above.
- Plus: for `list(range(100, 0, -1))` (100 numbers descending),
  `insertion_sort` equals `sorted` of the same input; for the interval list
  `[(i, i + 2) for i in range(0, 20, 3)]`, `merge_intervals` equals
  `[(0, 19)]`; `mode` of `[i % 7 for i in range(70)]` equals `0`.
