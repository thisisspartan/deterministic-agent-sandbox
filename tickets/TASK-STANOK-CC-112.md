# TASK-STANOK-CC-112 — wordfreq utility (word-frequency CLI)

impl: src/wordfreq.py
test: tests/wordfreq_test.py
docs: docs/wordfreq.md

## Goal

Implement a small, deterministic word-frequency CLI in `src/wordfreq.py`
(Python 3.11 stdlib only). It reads text from a file argument or from stdin,
tokenizes it into words, counts frequencies, and prints one `<word> <count>`
line per word, sorted by count DESCENDING then word ASCENDING (lexicographic).
Keep it minimal — this is a small, self-contained utility.

## Behavior contract

- Invocation: `python3 src/wordfreq.py [FILE]`.
  - If FILE is given and readable, read text from it.
  - Otherwise read text from stdin.
- Tokenization: lowercase the text; a "word" is a maximal run of ASCII
  letters or digits (`[a-z0-9]+`). Everything else (punctuation, whitespace,
  non-ASCII) is a separator and is dropped.
- Output: one line per distinct word, format `<word> <count>` (single space,
  no trailing spaces, no header). Sort by count descending, then word
  ascending.
- Empty input (no words) → print nothing, exit 0.
- Exit 0 on success. If FILE is given but missing/unreadable → print an error
  to stderr and exit 2.

## Module API (must be importable for tests)

`src/wordfreq.py` must expose, at module level:
- `tokenize(text: str) -> list[str]` — lowercased word tokens, order preserved.
- `frequencies(tokens: list[str]) -> dict[str, int]` — word → count.
- `format_report(freq: dict[str, int]) -> str` — the full report: sorted
  `<word> <count>` lines joined by `\n`, no trailing newline; empty dict → `""`.
- `main(argv: list[str] | None = None) -> int` — the CLI entry point; returns
  the exit code. Guarded by `if __name__ == "__main__": raise SystemExit(main())`.

## Test contract — `tests/wordfreq_test.py` (write it FIRST, TDD red→green)

pytest `def test_*`; `import wordfreq` works via `pythonpath=src`. Cover at
least:
- `tokenize`: mixed case → lowercased; punctuation/whitespace dropped;
  digits kept; non-ASCII separators dropped; empty string → `[]`.
- `frequencies`: counts correctly; empty list → `{}`.
- `format_report`: sorts by count desc then word asc; exact `<word> <count>`
  line format; empty dict → `""`.
- `main`: reads from a temp file (write it under `$TMPDIR`, delete it after);
  missing file → returns 2. (The stdin/empty path is covered by the smoke run.)

## Docs (`docs/wordfreq.md`)

A few lines: what it does, how to run (file arg and stdin), the tokenization
rule, the sort order, and the exit codes.

## Stack (fixed — do not deviate)

- Python 3.11 **stdlib only**, ZERO external dependencies. `node` is NOT
  available; `python3.11` IS preinstalled.
- Single module `src/wordfreq.py`. Do NOT create a `src/wordfreq/` package.
- ONE new test file: `tests/wordfreq_test.py`.
- `scripts/run.sh` ALREADY EXISTS and dispatches by extension — use it as-is,
  do NOT rewrite it.

## Acceptance

- `bash scripts/run.sh test tests/wordfreq_test.py` → exit 0.
- `bash scripts/run.sh smoke src/wordfreq.py` → exit 0 (smoke runs the module
  with stdin=/dev/null; empty input must print nothing and exit 0).
- No new files beyond `src/wordfreq.py`, `tests/wordfreq_test.py`,
  `docs/wordfreq.md`. No external dependencies. No `conftest.py`/`pytest.ini`/
  `pyproject.toml` under `tests/`.

## Time discipline (required)

- Work order: (1) write `tests/wordfreq_test.py`, (2) run it (red),
  (3) implement `src/wordfreq.py`, (4) re-run (green), (5) write
  `docs/wordfreq.md`.
- Run the test suite at most 2–3 times total.
- Any scratch file goes ONLY under `$TMPDIR` and must be deleted before you
  finish.

Final report (STRICTLY <= 5 lines):
1. TASK: DONE
2. Files: <list>
3. Tests: PASS
