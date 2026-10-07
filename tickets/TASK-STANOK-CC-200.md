# TASK-STANOK-CC-200: smoke modular arithmetic

impl: src/smoke_mod.py
test: tests/smoke_mod_test.py
run.sh: exists

## Deliverable

`src/smoke_mod.py` — three pure functions (no imports; no randomness).

1. `mod_pow(base, exp, m) -> int`
   - `base ** exp mod m` via fast (binary) exponentiation; `m == 1` → 0;
     `exp == 0` → `1 % m`. `exp >= 0` always in this contract.
   - Vectors: `(2, 10, 1000)` → 24; `(3, 0, 7)` → 1; `(5, 3, 5)` → 0;
     `(2, 200, 1000)` → 376; `(7, 1, 3)` → 1; `(10, 5, 1)` → 0.

2. `mod_inverse(a, m)`
   - Modular inverse of `a` mod `m` (result in `0..m-1`) via extended
     Euclidean algorithm; `None` when `gcd(a, m) != 1`.
   - Vectors: `(3, 7)` → 5; `(10, 17)` → 12; `(1, 7)` → 1;
     `(2, 4)` → None; `(0, 7)` → None.

3. `is_prime(n) -> bool`
   - Deterministic primality by trial division; `n < 2` → False.
   - Vectors: 0 → False; 1 → False; 2 → True; 3 → True; 4 → False;
     97 → True; 100 → False; 7919 → True; 1000003 → True.

## Acceptance

- `bash scripts/run.sh test` exits 0 (all tests green).
- `tests/smoke_mod_test.py` covers every vector above.
- Plus: for a fixed list of 20 triples `(base, exp, m)` (deterministic,
  e.g. derived from a seeded `random.Random(3)`), `mod_pow` equals the
  builtin `pow(base, exp, m)`.
- Plus: for every `n` in `range(2000)`, `is_prime(n)` equals the reference
  trial-division result.
- Plus: for a fixed list of 20 pairs `(a, m)`: when `mod_inverse(a, m)` is
  not None, `a * inv % m == 1`; when it is None, `math.gcd(a, m) != 1`.
