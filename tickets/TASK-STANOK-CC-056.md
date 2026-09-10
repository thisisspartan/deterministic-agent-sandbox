# TASK-STANOK-CC-056 — Levenshtein edit distance (pipeline e2e test ticket)

Status: `[ ] TODO`

Purpose: end-to-end pipeline test — a small, fully specified pure-logic feature
that validates the machine loop (TDD session -> verifier -> summary.json).

## 1. Feature: `src/levenshtein.js`

CommonJS module, no dependencies, exports exactly one function:

### `levenshtein(a, b)`
- Inputs: two strings `a`, `b`.
- Returns: the Levenshtein edit distance — the minimum number of single-character
  insertions, deletions, and substitutions to transform `a` into `b`
  (each operation costs 1). Non-negative integer.
- Throws `TypeError` if either argument is not a string (numbers, null, undefined, arrays, booleans).

## 2. Tests: `tests/levenshtein.test.js`

Run: `bash scripts/run.sh test tests/levenshtein.test.js` (single-file mode).
Use `node:test` + `node:assert/strict` only. Cover at minimum:

- Basics: ("", "") -> 0, ("abc", "abc") -> 0, ("", "abc") -> 3, ("abc", "") -> 3.
- Classic: ("kitten", "sitting") -> 3, ("flaw", "lawn") -> 2, ("sunday", "saturday") -> 3.
- Single ops: ("a", "") -> 1, ("ab", "a") -> 1, ("a", "b") -> 1, ("ab", "ba") -> 2.
- Symmetry: for the sample pairs above, `levenshtein(a, b) === levenshtein(b, a)`.
- Throws: `TypeError` for (123, "x"), ("x", null), (undefined, "x"), ([], "x"), (true, "x").

Real assertions only — no empty tests.

## 3. Docs: `docs/levenshtein.md`

Brief: API (params, return, thrown errors), definition of the distance,
a few examples.

## 4. Acceptance criteria

- `bash scripts/run.sh test tests/levenshtein.test.js` — all tests pass.
- Files created: `src/levenshtein.js`, `tests/levenshtein.test.js`, `docs/levenshtein.md` (nothing else).
- No external dependencies, CommonJS only.
