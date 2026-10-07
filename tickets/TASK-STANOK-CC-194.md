# TASK-STANOK-CC-194: smoke grid statistics

impl: src/smoke_grid.py
test: tests/smoke_grid_test.py
run.sh: exists

## Deliverable

`src/smoke_grid.py` — three pure functions over rectangular grids
(lists of lists of ints; no imports; no randomness):

1. `grid_sum(grid) -> int`
   - Sum of all cells; empty grid → 0.
   - Vectors: `[]` → 0; `[[1,2],[3,4]]` → 10; `[[-1,2],[3,-4]]` → 0;
     `[[7]]` → 7.

2. `row_maxes(grid) -> list`
   - Max of each row, in row order; empty grid → `[]`.
   - Vectors: `[]` → `[]`; `[[1,3],[2,9]]` → `[3,9]`; `[[-5]]` → `[-5]`;
     `[[1,2,3]]` → `[3]`.

3. `col_sums(grid) -> list`
   - Sum of each column (rectangular grid); empty grid → `[]`.
   - Vectors: `[]` → `[]`; `[[1,2,3],[4,5,6]]` → `[5,7,9]`;
     `[[1,2],[3,4]]` → `[4,6]`; `[[10]]` → `[10]`.

## Acceptance

- `bash scripts/run.sh test` exits 0 (all tests green).
- `tests/smoke_grid_test.py` covers every vector above.
- Plus: a fixed deterministic 5x7 grid (e.g. `[[i*7+j for j in range(7)]
  for i in range(5)]`): `grid_sum` equals the builtin
  `sum(sum(row) for row in grid)`; `row_maxes` equals
  `[max(row) for row in grid]`; `col_sums` equals the `zip(*grid)`
  reference `[sum(col) for col in zip(*grid)]`.
- Plus: a fixed 3x3 grid with negatives where `grid_sum` is 0
  (hand-computed in the test).
