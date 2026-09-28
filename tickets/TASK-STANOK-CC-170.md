# TASK-STANOK-CC-170: smoke string utilities

impl: src/smoke_str.py
test: tests/smoke_str_test.py
run.sh: exists

## Task

Implement small string utilities in `src/smoke_str.py` (pure stdlib, no third-party
imports) and cover them with pytest in `tests/smoke_str_test.py`.

Functions:

1. `reverse_words(s: str) -> str` — reverse the ORDER of whitespace-separated
   words, preserving the original single-space separation; leading/trailing
   whitespace is stripped; multiple internal spaces collapse to one.
   Empty string or whitespace-only string returns `""`.
2. `is_palindrome(s: str) -> bool` — True if `s` reads the same forwards and
   backwards, case-insensitive, ignoring non-alphanumeric characters
   (letters and digits only, ASCII). Empty result after filtering → False.
3. `count_vowels(s: str) -> int` — count ASCII vowels (a e i o u, both cases).

## Requirements

- No network, no files, no global state.
- All functions accept `str` and are total (no exceptions for any string input).

## Acceptance criteria

- `bash scripts/run.sh test` passes with the new tests green.
- `tests/smoke_str_test.py` covers: word reversal (single word, multiple words,
  extra/leading/trailing spaces, empty/whitespace-only), palindrome (exact,
  case-insensitive, with punctuation/spaces, digits, empty-after-filter → False),
  vowel counting (mixed case, no vowels, digits/punctuation ignored).
