# TASK-STANOK-CC-198: smoke diagonal statistics

impl: src/smoke_diag.py
test: tests/smoke_diag_test.py
run.sh: exists

## Deliverable

`src/smoke_diag.py` — three pure functions over square matrices (lists of
lists of ints; no imports; no randomness):

1. `main_diag(matrix) -> list`
   - Main diagonal (top-left to bottom-right); empty matrix → `[]`.
   - Vectors: `[]` → `[]`; `[[5]]` → `[5]`; `[[1,2],[3,4]]` → `[1,4]`;
     `[[1,2,3],[4,5,6],[7,8,9]]` → `[1,5,9]`.

2. `anti_diag(matrix) -> list`
   - Anti-diagonal (top-right to bottom-left); empty matrix → `[]`.
   - Vectors: `[]` → `[]`; `[[5]]` → `[5]`; `[[1,2],[3,4]]` → `[2,3]`;
     `[[1,2,3],[4,5,6],[7,8,9]]` → `[3,5,7]`.

3. `diag_sum(matrix) -> int`
   - Sum of the main diagonal; empty matrix → 0.
   - Vectors: `[]` → 0; `[[5]]` → 5; `[[1,2],[3,4]]` → 5;
     `[[1,2,3],[4,5,6],[7,8,9]]` → 15.

## Acceptance

- `bash scripts/run.sh test` exits 0 (all tests green).
- `tests/smoke_diag_test.py` covers every vector above.
- Plus: a fixed deterministic 6x6 matrix (e.g.
  `[[i*6+j for j in range(6)] for i in range(6)]`): `main_diag` equals
  `[m[i][i] for i in range(6)]`; `anti_diag` equals
  `[m[i][5-i] for i in range(6)]`; `diag_sum` equals
  `sum(main_diag(m))`.
- Plus: a fixed 4x4 matrix with negatives where `diag_sum` is 0
  (hand-computed in the test).
