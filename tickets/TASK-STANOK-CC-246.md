# TASK-STANOK-CC-246: Line statistics — a small pure-text module

impl: src/linestats.py
test: tests/linestats_test.py
docs: docs/linestats.md

run.sh: exists

## Context

A self-contained feature ticket (stdlib only, no I/O, no network), normal py
ticket for the existing stack (pytest via scripts/run.sh).

## Requirement

`src/linestats.py` must provide:

1. `line_count(text)` -> int: number of lines; a trailing newline does not
   add an empty line; empty string -> 0.

2. `blank_line_count(text)` -> int: lines that are empty or whitespace-only.

3. `longest_line(text)` -> the longest line by character count; ties ->
   the FIRST occurrence; empty text -> "".

Stdlib only. No file/socket I/O.

## Tests (`tests/linestats_test.py`, pytest)

Cover at least: empty text (0 / 0 / ""); single line; trailing newline not
counted as an extra line; CRLF and LF inputs give the same line count;
whitespace-only lines counted as blank; longest line exact value and
first-wins tie-break; lines with unicode characters counted by characters.
