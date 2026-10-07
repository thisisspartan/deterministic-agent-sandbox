# TASK-STANOK-CC-192: smoke digit statistics

impl: src/smoke_digits.py
test: tests/smoke_digits_test.py
run.sh: exists

## Deliverable

`src/smoke_digits.py` — three pure functions (no imports; no randomness):

1. `digit_product(n) -> int`
   - Product of the decimal digits of `abs(n)`.
   - Vectors: `0` → 0; `7` → 7; `123` → 6; `105` → 0; `-24` → 8.

2. `is_palin_number(n) -> bool`
   - True iff the decimal representation of `n` is a palindrome.
   - Negative numbers → False (the minus sign breaks symmetry).
   - Vectors: `0` → True; `7` → True; `121` → True; `12321` → True;
     `123` → False; `-121` → False.

3. `sum_of_squares_of_digits(n) -> int`
   - Sum of squares of the decimal digits of `abs(n)`.
   - Vectors: `0` → 0; `10` → 1; `123` → 14; `-12` → 5; `99` → 162.

## Acceptance

- `bash scripts/run.sh test` exits 0 (all tests green).
- `tests/smoke_digits_test.py` covers every vector above.
- Plus: for a fixed deterministic list of 100 integers (e.g.
  `list(range(-50, 50))`), `digit_product(n) == digit_product(abs(n))`
  for all of them.
- Plus: for the same list, `sum_of_squares_of_digits(n)` matches a
  string-based reference (`sum(int(c)**2 for c in str(abs(n)))`).
- Plus: `is_palin_number` on the same list matches the string reference
  (`str(n) == str(n)[::-1]`).
