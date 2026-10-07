# TASK-STANOK-CC-205: smoke rotation utilities

impl: src/smoke_rot.py
test: tests/smoke_rot_test.py
run.sh: exists

## Deliverable

`src/smoke_rot.py` — three pure functions (no imports; no randomness).
Inputs are never mutated.

1. `rotate_left(items, k) -> list`
   - Move the first `k` elements to the end; `k` may exceed `len(items)`
     (normalize with `k % len`); empty list → empty list.
   - Vectors: `([], 3)` → `[]`; `([1,2,3], 0)` → `[1,2,3]`;
     `([1,2,3], 1)` → `[2,3,1]`; `([1,2,3], 4)` → `[2,3,1]`;
     `([1,2,3,4], 2)` → `[3,4,1,2]`.

2. `rotate_right(items, k) -> list`
   - Move the last `k` elements to the front (normalize `k % len`);
     empty → empty.
   - Vectors: `([], 5)` → `[]`; `([1,2,3], 0)` → `[1,2,3]`;
     `([1,2,3], 1)` → `[3,1,2]`; `([1,2,3], 4)` → `[3,1,2]`;
     `([1,2,3,4], 2)` → `[3,4,1,2]`.

3. `caesar(text, k) -> str`
   - Shift each ASCII letter by `k` positions, wrapping within its own case
     (a–z, A–Z); non-letters unchanged; `k` may be negative or > 26.
   - Vectors: `("", 7)` → `""`; `("abc", 1)` → `"bcd"`;
     `("xyz", 3)` → `"abc"`; `("ABC", -1)` → `"ZAB"`;
     `("Hello, World!", 3)` → `"Khoor, Zruog!"`; `("aA", 26)` → `"aA"`.

## Acceptance

- `bash scripts/run.sh test --all` exits 0 (all tests green).
- `tests/smoke_rot_test.py` covers every vector above.
- Plus: for a fixed deterministic list `list(range(50))` and `k=17`:
  `rotate_left(items, 17)` equals the reference
  `items[17:] + items[:17]`; `rotate_right(items, 17)` equals the reference
  `items[-17:] + items[:-17]`; `caesar("The quick brown fox", 13)` equals the
  reference `caesar(caesar("The quick brown fox", 13), 13)` decoded back by
  `caesar(..., 13)` — i.e. `caesar(caesar(s, 13), 13)` returns `s`.
