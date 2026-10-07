# TASK-STANOK-CC-203: smoke counting utilities

impl: src/smoke_count.py
test: tests/smoke_count_test.py
run.sh: exists

## Deliverable

`src/smoke_count.py` — three pure functions over lists of ints (no imports;
no randomness). Inputs are never mutated.

1. `count_greater(nums, x) -> int`
   - Number of elements strictly greater than `x`; empty → 0.
   - Vectors: `([], 0)` → 0; `([1,2,3], 2)` → 1; `([1,2,3], 3)` → 0;
     `([-1,-2], -2)` → 1; `([5], 5)` → 0.

2. `count_between(nums, lo, hi) -> int`
   - Number of elements `v` with `lo <= v <= hi` (inclusive); empty → 0.
   - Vectors: `([], 0, 1)` → 0; `([1,2,3,4], 2, 3)` → 2;
     `([1,2,3,4], 5, 6)` → 0; `([-1,0,1], -1, 1)` → 3; `([2], 2, 2)` → 1.

3. `count_signs(nums) -> tuple`
   - `(negatives, zeros, positives)`; empty → `(0, 0, 0)`.
   - Vectors: `[]` → `(0,0,0)`; `[0,0]` → `(0,2,0)`; `[-1,0,2]` → `(1,1,1)`;
     `[-5,-3]` → `(2,0,0)`; `[7]` → `(0,0,1)`.

## Acceptance

- `bash scripts/run.sh test` exits 0 (all tests green).
- `tests/smoke_count_test.py` covers every vector above.
- Plus: for a fixed deterministic list of 100 ints (e.g. a seeded
  `random.Random(17)` sample): `count_greater(nums, 0)` equals the
  reference `sum(1 for v in nums if v > 0)`; `count_between(nums, -10, 10)`
  equals the reference `sum(1 for v in nums if -10 <= v <= 10)`;
  `count_signs(nums)` equals the reference
  `(sum(1 for v in nums if v < 0), sum(1 for v in nums if v == 0),
  sum(1 for v in nums if v > 0))`.
