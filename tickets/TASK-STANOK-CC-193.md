# TASK-STANOK-CC-193: smoke bounds statistics

impl: src/smoke_bounds.py
test: tests/smoke_bounds_test.py
run.sh: exists

## Deliverable

`src/smoke_bounds.py` — three pure functions (no imports; no randomness):

1. `min_max(nums) -> tuple`
   - `(min, max)` of the list; `([],)` → `(None, None)`.
   - Vectors: `[]` → `(None, None)`; `[5]` → `(5, 5)`; `[3,1,2]` →
     `(1, 3)`; `[-4, 7, -4]` → `(-4, 7)`.

2. `span(nums) -> int | None`
   - `max(nums) - min(nums)`; `None` for an empty list.
   - Vectors: `[]` → None; `[5]` → 0; `[3,1,2]` → 2; `[-4, 7]` → 11.

3. `within(value, lo, hi) -> bool`
   - Inclusive bounds: `lo <= value <= hi`.
   - Vectors: `(5, 1, 10)` → True; `(0, 1, 10)` → False;
     `(11, 1, 10)` → False; `(1, 1, 10)` → True; `(10, 1, 10)` → True.

## Acceptance

- `bash scripts/run.sh test` exits 0 (all tests green).
- `tests/smoke_bounds_test.py` covers every vector above.
- Plus: for a fixed deterministic list of 200 integers (e.g. a seeded
  `random.Random(7)` permutation of `range(200)` plus a few negatives),
  `min_max(nums) == (min(nums), max(nums))` and
  `span(nums) == max(nums) - min(nums)` (builtin references).
- Plus: `within` on a fixed grid of (value, lo, hi) triples matches the
  builtin expression `lo <= value <= hi`.
