# TASK-STANOK-CC-169: smoke date utilities

impl: src/smoke_date.py
test: tests/smoke_date_test.py
run.sh: exists

## Task

Implement small date utilities in `src/smoke_date.py` (pure stdlib, no third-party
imports) and cover them with pytest in `tests/smoke_date_test.py`.

Functions (all take and return ISO `YYYY-MM-DD` strings unless noted):

1. `is_weekend(date_str: str) -> bool` — True for Saturday/Sunday.
2. `add_business_days(date_str: str, n: int) -> str` — advance `n` business days
   (Monday–Friday); `n=0` returns the input unchanged; `n` is a non-negative int.
3. `month_name(date_str: str) -> str` — English month name (`"January"` … `"December"`).

## Requirements

- Invalid date strings (not `YYYY-MM-DD`, or impossible dates like `2026-02-31`)
  must raise `ValueError` in all three functions.
- `add_business_days` must skip weekends correctly across month and year
  boundaries (e.g. a Friday + 1 business day = the following Monday).
- No network, no files, no global state.

## Acceptance criteria

- `bash scripts/run.sh test` passes with the new tests green.
- `tests/smoke_date_test.py` covers: weekend/weekday detection, `n=0`,
  weekend skip, month boundary, year boundary (Dec→Jan), all 12 month names,
  and `ValueError` on invalid input for each function.
