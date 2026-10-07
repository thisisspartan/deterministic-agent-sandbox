# TASK-STANOK-CC-190: smoke sort statistics

impl: src/smoke_sort.py
test: tests/smoke_sort_test.py
run.sh: exists

## Deliverable

`src/smoke_sort.py` — three pure functions (no imports beyond the standard
library; no randomness in the functions themselves):

1. `is_sorted(nums, strict=False) -> bool`
   - `strict=False`: non-decreasing (equal neighbours allowed).
   - `strict=True`: strictly increasing.
   - Vectors: `[]` → True; `[1]` → True; `[1,2,2,3]` → True (non-strict);
     `[1,2,2,3]` strict → False; `[3,2,1]` → False; `[1,1]` → True
     (non-strict); `[1,1]` strict → False.

2. `count_inversions(nums) -> int`
   - Number of index pairs `i < j` with `nums[i] > nums[j]`.
   - Vectors: `[]` → 0; `[1,2,3]` → 0; `[3,2,1]` → 3; `[2,4,1,3]` → 3
     (pairs (2,1), (4,1), (4,3)); `[1,1,1]` → 0; `[5,1]` → 1.

3. `kth_smallest(nums, k) -> int | None`
   - 1-based k-th smallest value (duplicates count as separate positions).
   - `None` when `k < 1` or `k > len(nums)`.
   - Vectors: `[3,1,2]` k=1 → 1; k=2 → 2; k=3 → 3; k=0 → None; k=4 → None;
     `[]` k=1 → None; `[7,7,7]` k=2 → 7.

## Acceptance

- `bash scripts/run.sh test` exits 0 (all tests green).
- `tests/smoke_sort_test.py` covers every vector above.
- Plus: a brute-force O(n²) reference for `count_inversions` checked against
  the implementation on a fixed 200-element list (deterministic, e.g.
  `list(range(200, 0, -1))` and a seeded `random.Random(42)` permutation).
- Plus: `is_sorted` on the same 200-element descending list → False,
  on its sorted copy → True.
