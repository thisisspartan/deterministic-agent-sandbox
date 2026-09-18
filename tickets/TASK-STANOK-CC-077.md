# TASK-STANOK-CC-077 — Rebuild smoke: `add` module (Docker pipeline verification)

impl: src/smoke.js
test: tests/smoke.test.js
docs: docs/smoke.md

Implement the `smoke` module: a minimal arithmetic module used to exercise the
full machine loop (test red -> implement -> green -> docs).

## Contract (exact — your tests must assert these)

- `src/smoke.js` exports `add(a, b)` via CommonJS (`module.exports = { add }`),
  returning the numeric sum `a + b`.
- `tests/smoke.test.js` covers at least: `add(2, 3) === 5`, `add(-1, 1) === 0`,
  `add(0, 0) === 0`.
- `docs/smoke.md` documents the module contract in a few lines.

## Notes

- Match the project's EXISTING stack: look at `scripts/run.sh` and the existing
  test files before writing anything. Do not introduce a second language or
  test framework.
- Run your test with `bash scripts/run.sh test tests/smoke.test.js`.

Final report (STRICTLY <= 5 lines):
1. TASK: DONE
2. Files: <list>
3. Tests: PASS
