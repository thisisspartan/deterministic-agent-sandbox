# TASK-STANOK-CC-195: smoke frequency statistics

impl: src/smoke_freq.py
test: tests/smoke_freq_test.py
run.sh: exists

## Deliverable

`src/smoke_freq.py` — three pure functions (no imports; no randomness):

1. `freq_table(items) -> dict`
   - Count of each item; empty list → `{}`.
   - Vectors: `[]` → `{}`; `["a","b","a"]` → `{"a": 2, "b": 1}`;
     `[1,1,2,2,2]` → `{1: 2, 2: 3}`.

2. `top_k(freq, k) -> list`
   - The `k` most frequent `(item, count)` pairs, sorted by count
     DESCENDING, ties by item ASCENDING (items are comparable).
     `k >= len(freq)` → all pairs; empty freq → `[]`.
   - Vectors: `{"a":2,"b":2,"c":1}` k=2 → `[("a",2),("b",2)]` (tie a/b);
     same freq k=1 → `[("a",2)]`; same freq k=5 →
     `[("a",2),("b",2),("c",1)]`; `{}` k=3 → `[]`.

3. `unique_count(items) -> int`
   - Number of distinct items; empty list → 0.
   - Vectors: `[]` → 0; `[1,1,1]` → 1; `[1,2,3]` → 3;
     `["x","y","x"]` → 2.

## Acceptance

- `bash scripts/run.sh test` exits 0 (all tests green).
- `tests/smoke_freq_test.py` covers every vector above.
- Plus: for a fixed deterministic list of 100 items (e.g.
  `[i % 10 for i in range(100)]`): `sum(freq_table(items).values()) ==
  len(items)`; `sum(c for _, c in top_k(freq, len(freq))) == len(items)`;
  `unique_count(items) == len(freq_table(items))`.
- Plus: `top_k` on a fixed 5-key freq dict with all-distinct counts
  returns the keys in descending-count order (hand-computed in the test).
