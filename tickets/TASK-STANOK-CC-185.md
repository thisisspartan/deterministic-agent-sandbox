# TASK-STANOK-CC-185: smoke hash utilities

impl: src/smoke_hash.py
test: tests/smoke_hash_test.py
run.sh: exists

## Task

Implement small, pure hash utilities in `src/smoke_hash.py`
(pure stdlib, no third-party imports) and cover them with pytest in
`tests/smoke_hash_test.py`.

All functions take `bytes` input and return a non-negative `int`.

Functions:

1. `fnv1a_32(data: bytes) -> int` — FNV-1a, 32-bit.
   Offset basis `2166136261` (`0x811C9DC5`), prime `16777619`
   (`0x01000193`). For each byte `b` in order:
   `h = ((h ^ b) * 16777619) % 2**32`.
   `fnv1a_32(b"") == 2166136261`,
   `fnv1a_32(b"a") == 0x11565117`,
   `fnv1a_32(b"foobar") == 0x4F3CC8D6`.
2. `djb2(data: bytes) -> int` — DJB2, 32-bit.
   `h = 5381`; for each byte `b` in order:
   `h = (h * 33 + b) % 2**32`.
   `djb2(b"") == 5381`, `djb2(b"a") == 177670`.
3. `crc8(data: bytes, poly: int = 0x07) -> int` — classic CRC-8
   (no reflection, init `0`, no final XOR). For each byte `b`:
   `crc ^= b`, then 8 times:
   `crc = ((crc << 1) ^ (poly if crc & 0x80 else 0)) & 0xFF`.
   `crc8(b"") == 0`, `crc8(b"123456789") == 0xF4`.

## Requirements

- No network, no files, no global state.
- All functions are pure; input `bytes` is never mutated.
- Results are always masked to their width (32-bit or 8-bit) — never
  negative, never wider than the hash size.
- `crc8` must honour the `poly` argument (a different polynomial gives
  a different digest for the same input).

## Acceptance criteria

- `bash scripts/run.sh test` passes with the new tests green.
- `tests/smoke_hash_test.py` covers:
  - `fnv1a_32`: the three vectors above; a longer input (e.g.
    `b"hello world"` — assert determinism and 32-bit width, not a
    memorized constant); result is always `< 2**32`.
  - `djb2`: the two vectors above; a longer input (determinism +
    32-bit width); result is always `< 2**32`.
  - `crc8`: the two vectors above; a custom polynomial (e.g. `0x31`)
    differs from the default on a non-trivial input; result is always
    `< 256`; empty input is `0` for any polynomial.
  - width invariants: for a batch of random-ish byte strings, all three
    digests stay within their bit width.
