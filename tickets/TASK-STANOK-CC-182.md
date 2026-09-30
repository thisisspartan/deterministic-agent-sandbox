# TASK-STANOK-CC-182: smoke integer utilities

impl: src/smoke_int.py
test: tests/smoke_int_test.py
run.sh: exists

## Task

Implement small integer utilities in `src/smoke_int.py`
(pure stdlib, no third-party imports) and cover them with pytest in
`tests/smoke_int_test.py`.

Functions:

1. `digit_sum(n) -> int` — sum of the decimal digits of `n`
   (`n >= 0`). `digit_sum(123) == 6`, `digit_sum(0) == 0`.
   Raises `ValueError` for negative `n`.
2. `is_perfect(n) -> bool` — True iff `n > 0` and the sum of its proper
   divisors (divisors excluding `n` itself) equals `n`.
   `is_perfect(6) is True` (1+2+3), `is_perfect(28) is True`,
   `is_perfect(1) is False`, `is_perfect(12) is False`.
   Returns False for `n <= 0`.
3. `collatz_steps(n) -> int` — number of Collatz steps to reach 1
   (`n >= 1`): even → `n/2`, odd → `3n+1`, counting each transformation.
   `collatz_steps(1) == 0`, `collatz_steps(6) == 8`
   (6→3→10→5→16→8→4→2→1).
   Raises `ValueError` for `n < 1`.

## Requirements

- No network, no files, no global state.
- All functions are pure; no mutation of any input (inputs are ints).
- `is_perfect` must be efficient enough for `n` up to 10^6
   (trial division up to `sqrt(n)` is fine).

## Acceptance criteria

- `bash scripts/run.sh test` passes with the new tests green.
- `tests/smoke_int_test.py` covers: digit_sum (0, single digit, multi-digit,
  zeros inside such as 101, negative raises ValueError), is_perfect
  (6, 28, 496 True; 1, 12, 24, 100 False; 0 and negative False), and
  collatz_steps (1 → 0, 6 → 8, 7 → 16, a value with a known short chain
  such as 8 → 3, n < 1 raises ValueError).
