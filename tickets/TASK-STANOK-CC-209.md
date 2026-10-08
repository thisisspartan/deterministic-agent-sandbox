# TASK-STANOK-CC-209: smoke text utilities

impl: src/smoke_text.py
test: tests/smoke_text_test.py
run.sh: exists

## Deliverable

`src/smoke_text.py` — two pure functions (no imports; no randomness).
Inputs are never mutated.

1. `is_palindrome(text) -> bool`
   - Case-insensitive; only letters and digits are considered (all other
     characters ignored); empty string -> True.
   - Vectors: `""` -> True; `"a"` -> True; `"ab"` -> False;
     `"A man, a plan, a canal: Panama"` -> True; `"racecar"` -> True;
     `"race a car"` -> False; `"12321"` -> True; `"12345"` -> False.

2. `caesar(text, shift) -> str`
   - Shift each ASCII letter by `shift` positions, wrapping within its own
     case (a-z, A-Z); non-letters pass through unchanged; `shift` may be
     negative or larger than 26.
   - Vectors: `caesar("abc", 3)` -> `"def"`; `caesar("xyz", 3)` -> `"abc"`;
     `caesar("XYZ", 3)` -> `"ABC"`; `caesar("Hello, World!", 3)` ->
     `"Khoor, Zruog!"`; `caesar("abc", -1)` -> `"zab"`;
     `caesar("abc", 29)` -> `"def"`; `caesar("", 5)` -> `""`;
     `caesar("a1B2", 1)` -> `"b1C2"`.

## Acceptance

- `bash scripts/run.sh test --all` exits 0 (all tests green).
- `tests/smoke_text_test.py` covers every vector above.
- Plus: `is_palindrome` of `"".join(reversed(s)) + s` is True for
  `s = "Ab3c"`; `caesar(caesar(s, 7), -7) == s` for
  `s = "Mix3d Case! zZ"`.
