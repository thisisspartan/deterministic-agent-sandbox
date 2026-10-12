# TASK-STANOK-CC-255 — csv_stats: deterministic CSV column-stats utility

impl: src/csv_stats.py
test: tests/csv_stats_test.py
docs: docs/csv_stats.md

run.sh: exists

## Context

Project stack: Python, pytest (`tests/**/*_test.py`), entrypoint `scripts/run.sh` exists —
use it as-is. stdlib only (`csv`, `statistics`, `argparse`), no new dependencies.
Do not touch `scripts/`, `launcher/`, `k8s/`.

## Requirements

Module `src/csv_stats.py` — a deterministic CSV column-stats utility:

1. **Parsing**: CSV text with a header row (first row = column names) via the stdlib
   `csv` module. Rows whose field count differs from the header are skipped (malformed).
   Empty input or header-only input -> empty result.
2. **Numeric columns**: a cell is numeric iff `float(cell)` succeeds. For each column with
   at least one numeric cell: `min`, `max`, `mean`, `median` over its numeric cells only
   (non-numeric cells in that column are skipped). Columns with zero numeric cells are
   absent from the result.
3. **Top-N values**: `top_values(text, column, n)` -> list of `(value, count)` for numeric
   values of that column, sorted by count descending; ties broken by first occurrence in
   the file (stable). `n < 1` -> empty list. Unknown column -> `KeyError`.
4. **CLI** (`python -m src.csv_stats <file> [-c COLUMN] [-n N]`): without `-c`, print
   min/max/mean/median for every numeric column (columns sorted by name); with `-c`, print
   top-N values of that column (default N=10). Invalid arguments -> argparse standard
   behavior (exit code 2, message on stderr). Output format chosen by the implementation,
   must be deterministic (same input -> byte-identical output) and is pinned in tests/docs.
5. **Determinism**: no randomness, no locale or time dependence; iteration order of results
   is by column name.

## Tests (`tests/csv_stats_test.py`, at least 6 test functions)

Must cover at least:
- empty input and header-only input: empty result;
- malformed rows (field count mismatch) are skipped, valid rows still counted;
- mixed non-numeric cells in a numeric column are skipped; a fully non-numeric column is
  absent from the result;
- numeric forms: integers, negatives, decimals, exponent notation (`1e3`) parse correctly;
- median for odd and even counts (even -> average of the two middle values);
- top-N: counts correct; tie -> first occurrence in the file wins; `n < 1` -> empty;
  unknown column -> KeyError;
- argument errors: invalid flag and invalid `-n` via the CLI (subprocess) -> rc=2;
- larger input (~50 rows synthetic): all stats verified against expected values.

## Process

TDD: tests first; the red phase (RED CONFIRMED) must happen before the implementation.

## Out of scope

No changes to `scripts/run.sh`, `launcher/`, `k8s/`; no new dependencies; no extra features.
