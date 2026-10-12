# TASK-STANOK-CC-245: Word frequency — a small pure-text module

impl: src/wordfreq.py
test: tests/wordfreq_test.py
docs: docs/wordfreq.md

run.sh: exists

## Context

A self-contained feature ticket (stdlib only, no I/O, no network). It is a
normal py ticket for the existing stack (pytest via scripts/run.sh).

## Requirement

`src/wordfreq.py` must provide:

1. `tokenize(text)` -> list of lowercased word tokens: split on any
   non-alphanumeric, non-underscore character; tokens keep digits and
   underscores; empty tokens never appear.

2. `count_words(text)` -> `dict[str, int]` — token -> occurrences.

3. `top_words(text, n)` -> list of `(word, count)` tuples sorted by count
   descending, then by word ascending (lexicographic) for ties; `n` clamped
   to `[0, len(result)]`; `n <= 0` -> empty list.

Stdlib only (`re`, `collections.Counter`). No file/socket I/O.

## Tests (`tests/wordfreq_test.py`, pytest)

Cover at least: case folding ("Foo FOO foo" -> 3); punctuation/boundary
splitting ("a,b;c\nd" -> a,b,c,d); tokens with digits/underscores kept
("x_1" stays one token); empty text -> {} and top_words -> []; tie-break
lexicographic (equal counts -> alphabetical order); `n` clamping (n larger
than vocabulary -> whole vocabulary; n=0 and negative -> []); exact counts
for a pinned small text.
