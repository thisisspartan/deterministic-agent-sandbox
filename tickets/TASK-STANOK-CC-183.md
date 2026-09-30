# TASK-STANOK-CC-183: smoke base/roman conversions

impl: src/smoke_conv.py
test: tests/smoke_conv_test.py
run.sh: exists

## Task

Implement small, pure conversion utilities in `src/smoke_conv.py`
(pure stdlib, no third-party imports) and cover them with pytest in
`tests/smoke_conv_test.py`.

Functions:

1. `to_base(n, base) -> str` — convert a non-negative integer `n` to a
   string in the given `base` (2 <= base <= 36), lowercase digits
   (`0-9a-z`). `to_base(255, 16) == 'ff'`, `to_base(0, 2) == '0'`,
   `to_base(10, 2) == '1010'`.
   Raises `ValueError` for `n < 0` or `base` outside 2..36.
2. `from_base(s, base) -> int` — parse a non-empty string `s` of
   lowercase (or uppercase) digits in the given `base` (2 <= base <= 36)
   into an int. `from_base('ff', 16) == 255`, `from_base('1010', 2) == 10`.
   Raises `ValueError` for an empty string, a digit not valid in the
   base, or `base` outside 2..36.
3. `roman(n) -> str` — convert an integer `n` (1 <= n <= 3999) to a
   canonical uppercase Roman numeral. `roman(1) == 'I'`,
   `roman(4) == 'IV'`, `roman(9) == 'IX'`, `roman(40) == 'XL'`,
   `roman(90) == 'XC'`, `roman(400) == 'CD'`, `roman(900) == 'CM'`,
   `roman(1994) == 'MCMXCIV'`, `roman(3999) == 'MMMCMXCIX'`.
   Raises `ValueError` for `n < 1` or `n > 3999`.
4. `roman_value(s) -> int` — parse a canonical uppercase Roman numeral
   string into an int. `roman_value('MCMXCIV') == 1994`.
   Raises `ValueError` for an empty string, any character outside
   `MDCLXVI`, or a non-canonical numeral (e.g. `'IIII'`, `'VV'`,
   `'IC'` — a smaller value may not be subtracted from a value more
   than 10x larger, and no digit may repeat more than 3 times).

## Requirements

- No network, no files, no global state.
- All functions are pure; no mutation of any input.
- `to_base`/`from_base` must be inverses: `from_base(to_base(n, b), b) == n`
  for all `n >= 0` and `base` in 2..36.

## Acceptance criteria

- `bash scripts/run.sh test` passes with the new tests green.
- `tests/smoke_conv_test.py` covers:
  - `to_base`: 0, single digit, powers of the base, 255 in base 16,
    a value in base 36 using letters (e.g. `to_base(1295, 36) == 'zz'`),
    negative n raises ValueError, base 1 and base 37 raise ValueError.
  - `from_base`: round-trip with `to_base` for several bases,
    uppercase input accepted, empty string raises ValueError,
    invalid digit for the base raises ValueError (e.g. `'2'` in base 2),
    base outside 2..36 raises ValueError.
  - `roman`: the examples above plus 10, 50, 100, 500, 1000, 3999;
    n = 0 and n = 4000 raise ValueError.
  - `roman_value`: round-trip `roman_value(roman(n)) == n` for a spread
    of values (1, 4, 9, 40, 90, 400, 900, 1994, 3999); empty string,
    lowercase input, `'IIII'`, `'VV'`, `'IC'` raise ValueError.
