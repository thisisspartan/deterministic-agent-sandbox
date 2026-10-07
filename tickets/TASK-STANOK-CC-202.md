# TASK-STANOK-CC-202: smoke prefix scans

impl: src/smoke_scan.py
test: tests/smoke_scan_test.py
run.sh: exists

## Deliverable

`src/smoke_scan.py` — three pure functions over lists of ints (no imports;
no randomness). Each returns a NEW list of the same length; inputs are
never mutated.

1. `scan_max(nums) -> list`
   - Prefix maxima: result[i] = max(nums[0..i]); empty → `[]`.
   - Vectors: `[]` → `[]`; `[3]` → `[3]`; `[1,3,2,5]` → `[1,3,3,5]`;
     `[-2,-5,-1]` → `[-2,-2,-1]`.

2. `scan_min(nums) -> list`
   - Prefix minima: result[i] = min(nums[0..i]); empty → `[]`.
   - Vectors: `[]` → `[]`; `[3]` → `[3]`; `[3,1,2,0]` → `[3,1,1,0]`;
     `[5,5,5]` → `[5,5,5]`.

3. `scan_sum(nums) -> list`
   - Prefix sums (cumulative): result[i] = sum(nums[0..i]); empty → `[]`.
   - Vectors: `[]` → `[]`; `[1]` → `[1]`; `[1,2,3]` → `[1,3,6]`;
     `[-1,1,-1]` → `[-1,0,-1]`.

## Acceptance

- `bash scripts/run.sh test` exits 0 (all tests green).
- `tests/smoke_scan_test.py` covers every vector above.
- Plus: for a fixed deterministic list of 100 ints (e.g. a seeded
  `random.Random(13)` sample), all three functions equal the reference
  prefix computations
  (`[max(nums[:i+1]) for i in range(n)]`,
  `[min(nums[:i+1]) for i in range(n)]`,
  `[sum(nums[:i+1]) for i in range(n)]`).
