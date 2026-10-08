# TASK-STANOK-CC-210: smoke — container path proof (package entrypoint)

test: tests/smoke_slug_test.py
impl: src/smoke_slug.py

run.sh: exists

## Context

The launcher was refactored into a package (`launcher/`, A) and the hub was
gutted (C). The container-side entrypoint (`launcher/stanok.py` ->
`launcher.cli.main`) is exercised end-to-end only by a real sandbox run.
This ticket is that run: a trivial deliverable, the point is the full path
host -> docker -> container gates -> agent session -> verify -> summary.json.

## Requirement

`src/smoke_slug.py` — a module with one function:

`slug(text: str) -> str` — normalize text to a URL slug:
lowercase; replace runs of non-alphanumeric characters with a single `-`;
strip leading/trailing `-`; empty result -> `""`.

## Acceptance criteria

- `tests/smoke_slug_test.py` (pytest, `def test_*`) covers: basic phrase,
  punctuation runs collapse, leading/trailing separators stripped, digits
  preserved, empty/separator-only input -> `""`.
- `scripts/run.sh test tests/smoke_slug_test.py` -> rc=0 after the
  implementation; `scripts/run.sh test --all` -> rc=0.
