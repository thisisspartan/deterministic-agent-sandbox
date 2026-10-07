# TASK-STANOK-CC-196: smoke consecutive-run statistics

impl: src/smoke_runs.py
test: tests/smoke_runs_test.py
run.sh: exists

## Deliverable

`src/smoke_runs.py` — three pure functions over lists of ints (no imports;
no randomness). A "run" is a maximal contiguous subsequence where each
element is exactly +1 from the previous.

1. `count_runs(nums) -> int`
   - Number of runs; empty list → 0.
   - Vectors: `[]` → 0; `[1]` → 1; `[1,2,3]` → 1; `[1,2,4,5]` → 2;
     `[5,3,1]` → 3; `[1,2,4,5,7]` → 3.

2. `longest_run(nums) -> int`
   - Length of the longest run; empty list → 0.
   - Vectors: `[]` → 0; `[1]` → 1; `[1,2,3]` → 3; `[1,2,4,5]` → 2;
     `[5,3,1]` → 1; `[1,2,4,5,7]` → 2.

3. `run_starts(nums) -> list`
   - First value of each run, in order; empty list → `[]`.
   - Vectors: `[]` → `[]`; `[1,2,3]` → `[1]`; `[1,2,4,5,7]` → `[1,4,7]`;
     `[5,3,1]` → `[5,3,1]`.

## Acceptance

- `bash scripts/run.sh test` exits 0 (all tests green).
- `tests/smoke_runs_test.py` covers every vector above.
- Plus: for a fixed deterministic list of 200 ints (e.g. a seeded
  `random.Random(11)` sample with repeats), `count_runs(nums) == 1 +
  sum(1 for i in range(len(nums)-1) if nums[i+1] != nums[i] + 1)` (and 0
  for the empty case).
- Plus: `longest_run` matches a brute-force O(n²) reference on the same
  list.
- Plus: the sum of run lengths (derived from `run_starts` by walking the
  list) equals `len(nums)` on the same list.
