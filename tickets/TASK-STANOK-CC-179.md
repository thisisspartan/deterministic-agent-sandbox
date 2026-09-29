# TASK-STANOK-CC-179: smoke matrix utilities

impl: src/smoke_matrix.py
test: tests/smoke_matrix_test.py
run.sh: exists

## Task

Implement small matrix utilities in `src/smoke_matrix.py` (pure stdlib, no
third-party imports) and cover them with pytest in `tests/smoke_matrix_test.py`.

A matrix is a non-empty list of non-empty lists of numbers (rows), e.g.
`[[1, 2], [3, 4]]`.

Functions:

1. `transpose(m) -> list` — the transpose of a rectangular matrix (rows
   become columns).
   `transpose([[1, 2, 3], [4, 5, 6]]) == [[1, 4], [2, 5], [3, 6]]`.
2. `matrix_multiply(a, b) -> list` — the standard matrix product; `a` is
   m×n, `b` is n×p, the result is m×p.
   `matrix_multiply([[1, 2], [3, 4]], [[5, 6], [7, 8]]) == [[19, 22], [43, 50]]`.
   Raises `ValueError` when the inner dimensions do not match.
3. `is_square(m) -> bool` — True iff the matrix is non-empty, every row has
   the same length, and that length equals the number of rows. Ragged input
   gives `False` (no exception).

## Requirements

- No network, no files, no global state.
- `transpose` and `is_square` are total for any non-empty list of non-empty
  rows; `matrix_multiply` requires rectangular inputs with matching inner
  dimensions (otherwise `ValueError`).
- Inputs are not mutated; results contain plain numbers.

## Acceptance criteria

- `bash scripts/run.sh test` passes with the new tests green.
- `tests/smoke_matrix_test.py` covers: transpose (2×3, 1×1, identity,
  float entries), matrix multiply (2×2, 2×3 · 3×2, left and right identity,
  1×n · n×1, inner-dimension mismatch → ValueError), is_square (square,
  rectangular, ragged → False, 1×1 → True).
