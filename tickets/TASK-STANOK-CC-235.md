# TASK-STANOK-CC-235: pipeline smoke — a small TDD module (trace-visible run)

impl: src/text_stats.py
test: tests/text_stats_test.py
docs: docs/text_stats.md

run.sh: exists

## Context

A deliberately small functional ticket whose purpose is a normal, full TDD
cycle through the pipeline (test-first red phase via `scripts/run.sh test`,
implementation, green, full suite). Nothing exotic is required — the value of
the run is the process itself.

## Requirement

`src/text_stats.py` (stdlib only):
- `word_count(text)` -> `int`: number of whitespace-separated words in the
  string (`""` -> `0`).
- `top_words(text, n)` -> `list[tuple[str, int]]`: the `n` most frequent
  words with their counts, sorted by count descending, then by word
  ascending; words are lowercased; `n <= 0` -> `[]`; fewer distinct words
  than `n` -> return all of them.

`tests/text_stats_test.py` (pytest, `def test_*`): cover at least —
empty string, single word, repeated words (counts), case folding
(`"A a"` -> one word `"a"` with count 2), tie-breaking (equal counts ->
alphabetical), `n` larger than the distinct-word count, `n <= 0`, and
multi-line text (newlines are whitespace).

## Acceptance criteria

- `scripts/run.sh test tests/text_stats_test.py` -> rc=0; `scripts/run.sh test --all` -> rc=0.
- Create NO files other than the three declared ones.
