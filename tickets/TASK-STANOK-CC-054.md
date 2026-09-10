# TASK-STANOK-CC-054 — Roman numeral converter (pipeline e2e test ticket)

Status: `[ ] TODO`

Purpose: end-to-end pipeline test — a small, fully specified pure-logic feature
that validates the machine loop (TDD session -> verifier -> summary.json).

## 1. Feature: `src/roman.js`

CommonJS module, no dependencies, exports exactly two functions:

### `toRoman(n)`
- Input: integer `n`, 1..3999.
- Returns: canonical Roman numeral string (uppercase).
- Throws `RangeError` if `n < 1` or `n > 3999`.
- Throws `TypeError` if `n` is not an integer (floats, strings, null, undefined, booleans).

### `fromRoman(s)`
- Input: string `s`.
- Returns: integer value of a canonical Roman numeral.
- Throws `TypeError` if `s` is not a string.
- Throws `RangeError` if `s` is not a valid canonical Roman numeral.

Canonical form rules (both directions):
- Only symbols I, V, X, L, C, D, M (uppercase; lowercase is invalid).
- Subtractive pairs only: IV, IX, XL, XC, CD, CM.
- No symbol appears more than 3 times in a row.
- Values never increase left to right, except inside a subtractive pair.
- Empty string is invalid.

Invalid examples (must throw): `""`, `"IIII"`, `"MMMM"`, `"LC"`, `"XM"`, `"ix"`, `"IVX"`, `"IIV"`, `"VIV"`.

## 2. Tests: `tests/roman.test.js`

Run: `bash scripts/run.sh test tests/roman.test.js` (single-file mode).
Use `node:test` + `node:assert/strict` only. Cover at minimum:

- toRoman values: 1->I, 4->IV, 9->IX, 14->XIV, 49->XLIX, 99->XCIX,
  400->CD, 900->CM, 1994->MCMXCIV, 3999->MMMCMXCIX.
- toRoman throws: `RangeError` for 0, -5, 4000; `TypeError` for 3.5, "5", null, undefined.
- fromRoman values: "I"->1, "IV"->4, "MCMXCIV"->1994, "MMMCMXCIX"->3999.
- fromRoman round-trip: for every n in 1..3999, `fromRoman(toRoman(n)) === n`.
- fromRoman throws: `RangeError` for "", "IIII", "MMMM", "LC", "XM", "ix", "IVX", "IIV", "VIV";
  `TypeError` for 123, null.

Real assertions only — no empty tests.

## 3. Docs: `docs/roman.md`

Brief: API of both functions (params, return, thrown errors),
canonical-form rules, a few examples.

## 4. Acceptance criteria

- `bash scripts/run.sh test tests/roman.test.js` — all tests pass.
- Files created: `src/roman.js`, `tests/roman.test.js`, `docs/roman.md` (nothing else).
- No external dependencies, CommonJS only.
