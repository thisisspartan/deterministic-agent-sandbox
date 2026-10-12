# TASK-STANOK-CC-254 — text_stats: deterministic text-stats utility

impl: src/text_stats.py
test: tests/text_stats_test.py
docs: docs/text_stats.md

run.sh: exists

## Context

Project stack: Python, pytest (`tests/**/*_test.py`), entrypoint `scripts/run.sh` exists —
use it as-is. stdlib only, no new dependencies. Do not touch `scripts/`, `launcher/`, `k8s/`.

## Requirements

Module `src/text_stats.py` — a deterministic text-stats utility:

1. **Counting** of a given text: lines, words, characters.
   - characters: every character including newlines (`len(text)`);
   - lines: `str.splitlines()` semantics (a trailing newline does NOT add an empty line);
   - words: maximal runs of non-whitespace characters (`str.split()` semantics).
2. **Top-N words**: `top_words(text, n)` -> list of `(word, count)`, sorted by count
   descending; ties broken by first occurrence in the text (stable, deterministic).
   `n < 1` -> empty list.
3. **Input source**: `read_text(path=None)` — `path=None` reads all of stdin;
   a path reads that file.
4. **CLI** (`python -m src.text_stats [file] [-n N]`): default N=10; invalid arguments
   -> argparse standard behavior (exit code 2, message on stderr). Output format is chosen
   by the implementation but must be deterministic (same input -> byte-identical output)
   and is pinned in the tests and docs.
5. **Determinism**: no randomness, no locale dependence, no time dependence.

## Tests (`tests/text_stats_test.py`, at least 6 test functions)

Must cover at least:
- empty input: all counts zero, top list empty;
- Cyrillic and Unicode text: words counted correctly, case preserved (no case folding);
- CRLF input: line count matches `splitlines` semantics, `\r` never part of a word;
- tie in top-N: equal counts -> the word that occurs first in the text wins;
- argument errors: invalid flag and invalid `-n` value via the CLI (subprocess) -> rc=2;
- larger input (~10 KB synthetic text): counts and top-N verified against expected values.

## Process

TDD: tests first; the red phase (RED CONFIRMED) must happen before the implementation.

## Out of scope

No changes to `scripts/run.sh`, `launcher/`, `k8s/`; no new dependencies; no extra features.
