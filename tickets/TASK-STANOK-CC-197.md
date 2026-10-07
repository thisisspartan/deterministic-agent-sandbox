# TASK-STANOK-CC-197: smoke peak/valley statistics

impl: src/smoke_peaks.py
test: tests/smoke_peaks_test.py
run.sh: exists

## Deliverable

`src/smoke_peaks.py` — three pure functions over lists of ints (no imports;
no randomness). A peak at index i (1 <= i < n-1) requires
`nums[i] > nums[i-1]` AND `nums[i] > nums[i+1]` (strict). A valley is the
mirror image with `<`.

1. `count_peaks(nums) -> int`
   - Number of peaks; lists shorter than 3 → 0.
   - Vectors: `[]` → 0; `[1]` → 0; `[1,2]` → 0; `[1,2,1]` → 1;
     `[1,2,3]` → 0; `[1,3,2,4,1]` → 2; `[5,5,5]` → 0 (strict).

2. `count_valleys(nums) -> int`
   - Number of valleys; lists shorter than 3 → 0.
   - Vectors: `[]` → 0; `[3,1,3]` → 1; `[1,2,1]` → 0;
     `[2,1,2,1,2]` → 2; `[1,1,1]` → 0.

3. `peak_positions(nums) -> list`
   - Indices of peaks, ascending; empty/short list → `[]`.
   - Vectors: `[]` → `[]`; `[1,2,1]` → `[1]`; `[1,3,2,4,1]` → `[1,3]`;
     `[1,2,3]` → `[]`.

## Acceptance

- `bash scripts/run.sh test` exits 0 (all tests green).
- `tests/smoke_peaks_test.py` covers every vector above.
- Plus: for a fixed deterministic list of 200 ints (e.g. a seeded
  `random.Random(21)` sample), `count_peaks` equals the builtin reference
  `sum(1 for i in range(1, n-1) if nums[i] > nums[i-1] and nums[i] >
  nums[i+1])`; `count_valleys` equals the mirror reference;
  `peak_positions` equals the matching list comprehension.
- Plus: on a fixed zig-zag list `[1,3,1,3,1,3,1]`, `count_peaks == 3` and
  `count_valleys == 2` (hand-computed).
