# TASK-STANOK-CC-201: smoke permutation utilities

impl: src/smoke_perm.py
test: tests/smoke_perm_test.py
run.sh: exists

## Deliverable

`src/smoke_perm.py` — three pure functions over lists of ints (no imports;
no randomness). Inputs are never mutated.

1. `count_permutations(nums) -> int`
   - Number of DISTINCT permutations of the list, i.e.
     `n! / prod(c! for each value-count c)`; empty list → 1.
   - Vectors: `[]` → 1; `[1]` → 1; `[1,2]` → 2; `[1,1,2]` → 3;
     `[1,1,1]` → 1; `[1,2,3]` → 6.

2. `next_permutation(nums) -> list | None`
   - The next lexicographic permutation of `nums` (returned as a NEW
     list); `None` when `nums` is the last (fully descending) permutation.
   - Vectors: `[1,2,3]` → `[1,3,2]`; `[3,2,1]` → None;
     `[1,1,5]` → `[1,5,1]`; `[1,2,3,4]` → `[1,2,4,3]`.

3. `kth_permutation(elems, k) -> list | None`
   - The 0-based k-th lexicographic permutation of the SORTED form of
     `elems` (distinct ints); `None` when `k < 0` or `k >= n!`.
   - Vectors: `([1,2,3], 0)` → `[1,2,3]`; `([1,2,3], 5)` → `[3,2,1]`;
     `([1,2,3], 3)` → `[2,3,1]`; `([1,2], 2)` → None; `([1,2], -1)` → None.

## Acceptance

- `bash scripts/run.sh test` exits 0 (all tests green).
- `tests/smoke_perm_test.py` covers every vector above.
- Plus: for `elems = [1,2,3,4]`, build the reference list of all 24
  permutations in lexicographic order (e.g. via `itertools.permutations`
  sorted); assert `kth_permutation(elems, k)` equals reference `k` for
  every `k` in `range(24)`, and that chaining `next_permutation` from
  `[1,2,3,4]` reproduces the whole reference sequence and returns None
  after the last element.
