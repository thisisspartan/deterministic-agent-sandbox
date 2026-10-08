# TASK-STANOK-CC-214 — smoke: word count module

test: tests/wordcount_test.py
impl: src/wordcount.py

run.sh: exists

## Task

Create `src/wordcount.py` with `count_words(text)` returning the number of
words in `text`. A word is a maximal run of non-whitespace characters;
leading/trailing/multiple whitespace must not create empty words;
`count_words("") == 0`.

Create `tests/wordcount_test.py` covering: empty string -> 0; a single word;
multiple spaces/tabs/newlines between words; leading and trailing whitespace.

## Constraints

- No other files; no extra dependencies.
- Do not touch `scripts/run.sh` or any existing test.
