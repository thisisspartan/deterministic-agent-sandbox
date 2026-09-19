# TASK-STANOK-SMOKE-01 — Sandbox/env smoke: add()

impl: src/smoke.js
test: tests/smoke.test.js
docs: docs/smoke.md

This is a harness smoke, not a product feature. Its purpose is to force a complete
machine run (model turn -> Bash tool -> both sandbox layers -> external verifier)
and end with rc=0 / verifier=PASS. Keep it minimal so it fits in one turn.

## Contract
`src/smoke.js` exports `add(a, b)` -> the numeric sum.
`tests/smoke.test.js` (node:test + node:assert/strict) must assert at least:
- `add(2, 3) === 5`
- `add(-1, 1) === 0`
- `add(0, 0) === 0`

## Deliverables
1. `tests/smoke.test.js` — write FIRST; the red phase (failing test) is expected and correct.
2. `src/smoke.js` — implementation.
3. `docs/smoke.md` — one short paragraph describing the module contract.

## Verification
```
bash scripts/run.sh test tests/smoke.test.js
```

Final report (STRICTLY <= 5 lines):
1. TASK: DONE
2. Files: src/smoke.js, tests/smoke.test.js, docs/smoke.md
3. Tests: PASS
