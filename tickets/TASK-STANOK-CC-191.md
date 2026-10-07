# TASK-STANOK-CC-191: smoke word statistics

impl: src/smoke_words.py
test: tests/smoke_words_test.py
run.sh: exists

## Deliverable

`src/smoke_words.py` — three pure functions (no imports; no randomness):

1. `count_words(text) -> int`
   - Number of whitespace-separated tokens (any run of whitespace
     separates; leading/trailing whitespace ignored).
   - Vectors: `""` → 0; `"hello"` → 1; `"  a  b  "` → 2; `"a\nb\tc"` → 3.

2. `most_frequent_word(text) -> str | None`
   - Most frequent word, case-insensitive comparison; the returned value
     is lowercase. Ties → lexicographically smallest word.
   - `None` for empty input (no words).
   - Vectors: `""` → None; `"a b a c b"` → `"a"` (a=2, b=2, c=1 → tie a/b);
     `"the cat the dog the"` → `"the"`; `"Z z a"` → `"z"` (z=2, a=1).

3. `longest_word(text) -> str | None`
   - Longest word (original case preserved). Ties → the one that appears
     FIRST in the text. `None` for empty input.
   - Vectors: `""` → None; `"hi hello there"` → `"hello"` (hello=5,
     there=5 → first); `"a bb"` → `"bb"`; `"  x  "` → `"x"`.

## Acceptance

- `bash scripts/run.sh test` exits 0 (all tests green).
- `tests/smoke_words_test.py` covers every vector above.
- Plus: a fixed 500-character text (deterministic, e.g. a repeated
  sentence pattern) where the sum of per-word occurrence counts equals
  `count_words(text)`, and `most_frequent_word` returns one of the words
  actually present.
- Plus: `longest_word` on a fixed list of 50 words of varying lengths
  returns the expected word (computed by hand in the test).
