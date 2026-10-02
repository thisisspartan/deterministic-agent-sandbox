# TASK-STANOK-CC-187: smoke base32 codec

impl: src/smoke_b32.py
test: tests/smoke_b32_test.py
run.sh: exists

## Task

Implement a small, pure RFC 4648 base32 codec in `src/smoke_b32.py`
(pure stdlib, no third-party imports, no `base64` module usage) and
cover it with pytest in `tests/smoke_b32_test.py`.

Alphabet: `A-Z` then `2-7` (uppercase; A=0 … Z=25, 2=26 … 7=31).
Padding character `=`. Encoding always pads to a multiple of 8
characters; valid trailing-padding counts are 0, 1, 3, 4, or 6.

Functions:

1. `b32_encode(data: bytes) -> str` — encode bytes to base32 with
   `=` padding to a multiple of 8 characters.
   `b32_encode(b"") == ""`,
   `b32_encode(b"f") == "MY======"`,
   `b32_encode(b"fo") == "MZXQ===="`,
   `b32_encode(b"foo") == "MZXW6==="`,
   `b32_encode(b"foob") == "MZXW6YQ="`,
   `b32_encode(b"fooba") == "MZXW6YTB"`,
   `b32_encode(b"foobar") == "MZXW6YTBOI======"`.
2. `b32_decode(s: str) -> bytes` — decode a padded base32 string back
   to bytes. Accepts uppercase and lowercase input (case-insensitive).
   Raises `ValueError` on:
   - any character outside the alphabet plus `=`;
   - a `=` that is not in the final padding position(s);
   - a total length that is not 0 and not a multiple of 8;
   - a trailing-padding count not in {0, 1, 3, 4, 6}.
   `b32_decode("MZXW6YTB") == b"fooba"`,
   `b32_decode("MZXW6YTBOI=======") == b"foobar"`,
   `b32_decode("mzxw6ytb") == b"fooba"`.

## Requirements

- No network, no files, no global state.
- Both functions are pure; no mutation of inputs.
- `b32_decode(b32_encode(x)) == x` for every `x: bytes`.
- Do not use the `base64` standard-library module (hand-rolled codec).

## Acceptance criteria

- `bash scripts/run.sh test` passes with the new tests green.
- `tests/smoke_b32_test.py` covers:
  - `b32_encode`: all seven vectors above; output is always uppercase
    and either empty or a multiple of 8 characters; trailing-padding
    counts for input lengths 1..6 are 6, 4, 3, 1, 0, 6 respectively.
  - `b32_decode`: the three vectors above; lowercase input decodes
    the same as uppercase; every encode output round-trips
    (`b32_decode(b32_encode(x)) == x`) for input lengths 0..20
    (all residue classes mod 3).
  - `ValueError` cases: a digit `1` in the input (not in alphabet,
    e.g. `"M1XW6YTB"`); a `=` in the middle (`"M=ZXW6YT"`); a total
    length not a multiple of 8 (`"MY="` — 3 chars; `"MZXW6YTBO"` —
    9 chars); an invalid padding count (`"MZXW6Y=="` — 8 chars with
    2 trailing `=`); an all-padding block (`"========"` — 8 `=`).
