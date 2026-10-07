# TASK-STANOK-CC-199: smoke sliding-window statistics

impl: src/smoke_window.py
test: tests/smoke_window_test.py
run.sh: exists

## Deliverable

`src/smoke_window.py` — three pure functions over lists of ints (no imports;
no randomness). A "window" is a contiguous slice of exactly `k` elements.
If `k <= 0` or `k > len(nums)`, there are no windows.

1. `max_window_sum(nums, k) -> int`
   - Maximum sum over all windows of length k; no windows → 0.
   - Vectors: `([], 2)` → 0; `([5], 1)` → 5; `([1,2,3], 2)` → 5;
     `([1,2,3], 3)` → 6; `([1,2,3], 4)` → 0; `([-1,-2,-3], 2)` → -3.

2. `min_window_sum(nums, k) -> int`
   - Minimum sum over all windows of length k; no windows → 0.
   - Vectors: `([], 2)` → 0; `([1,2,3], 2)` → 3; `([-1,5,-2], 2)` → 3;
     `([1,2,3], 3)` → 6; `([1,2,3], 4)` → 0.

3. `window_count(nums, k, threshold) -> int`
   - Number of windows of length k whose sum is >= threshold;
     no windows → 0.
   - Vectors: `([1,2,3,4], 2, 5)` → 2 (windows 3,5,7);
     `([1,2,3,4], 2, 3)` → 3; `([1,2,3], 2, 10)` → 0;
     `([], 2, 0)` → 0.

## Acceptance

- `bash scripts/run.sh test` exits 0 (all tests green).
- `tests/smoke_window_test.py` covers every vector above.
- Plus: for a fixed deterministic list of 200 ints (e.g. a seeded
  `random.Random(11)` sample) with `k = 7`: `max_window_sum` and
  `min_window_sum` equal the reference
  `max/min(sum(nums[i:i+k]) for i in range(n - k + 1))`;
  `window_count(nums, 7, 0)` equals the reference
  `sum(1 for i in range(n - k + 1) if sum(nums[i:i+k]) >= 0)`.
