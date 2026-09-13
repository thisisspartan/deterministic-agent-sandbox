# TASK-STANOK-SMOKE-02 — Tracing smoke (Opik)

## Contract

Create `src/ping.js` exporting:

- `ping()` → returns the string `"pong"`.

Built-in Node.js modules only. No npm packages.

## Tests (write FIRST — `tests/ping.test.js`, expect RED)

Use `node:test` + `node:assert/strict`. Cover:

1. `ping()` returns `"pong"`.

## Verification

`bash scripts/run.sh test tests/ping.test.js` → all tests PASS.

## Deliverables

- `src/ping.js`
- `tests/ping.test.js`

## Final report (STRICTLY ≤ 5 lines)

1. TASK: DONE
2. Files: src/ping.js, tests/ping.test.js
3. Tests: PASS
