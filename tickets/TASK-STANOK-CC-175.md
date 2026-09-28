# TASK-STANOK-CC-175: smoke bit utilities (retry1 — verify existing implementation)

edit: src/smoke_bits.py
edit: tests/smoke_bits_test.py
run.sh: exists

## Task

`src/smoke_bits.py` and `tests/smoke_bits_test.py` already exist from a
prior run. Verify the implementation satisfies the contract below and the
tests are the correct reference; fix the IMPLEMENTATION in `src/smoke_bits.py`
if it has any gap. Do NOT weaken or change the test assertions to fit broken
code — the tests in `tests/` are the reference contract. If the implementation
already satisfies the tests, make no changes (or only the minimal change
needed to go green).

Contract (pure stdlib, no third-party imports, no network/files/global state):

1. `popcount(n: int) -> int` — number of 1-bits in `n`. Defined for
   `n >= 0` only; negative input raises `ValueError` (message mentions the
   value). `popcount(0) == 0`, `popcount(7) == 3`, `popcount(0xFF) == 8`.
2. `is_power_of_two(n: int) -> bool` — True iff `n == 2**k` for some
   `k >= 0`. `is_power_of_two(1) == True`, `is_power_of_two(2) == True`,
   `is_power_of_two(3) == False`, `is_power_of_two(0) == False`,
   `is_power_of_two(-16) == False`. Total over all ints (no exceptions).
3. `parity(n: int) -> bool` — True iff `popcount(n)` is odd. Defined for
   `n >= 0` only; negative input raises `ValueError` (message mentions the
   value). `parity(0) == False`, `parity(1) == True`, `parity(3) == True`,
   `parity(7) == False`, `parity(8) == True`.

Return types exactly as specified (int / bool / bool).

## Acceptance criteria

- `bash scripts/run.sh test tests/smoke_bits_test.py` passes green.
- `tests/smoke_bits_test.py` covers: popcount (0, 1, 7, 255, 2**64-1,
  powers of two → 1, negative → ValueError), is_power_of_two (0, 1, 2, 4,
  3, 5, 1024, 2**32, -1, -16), parity (0, 1, 2, 3, 7, 8, 255, negative →
  ValueError).
- The full suite (`bash scripts/run.sh test --all`) is green.
