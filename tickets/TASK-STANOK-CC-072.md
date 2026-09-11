# TASK-STANOK-CC-072 — Fire model (heat simulation)

## Contract

Create `src/fire_model.js` exporting:

- `createModel({width=80, height=24, seed=1337})` →
  `{ width, height, heat: Float64Array(width*height), prng: number }`.
  Row-major, row 0 = top. `heat` initialized to all zeros. `prng = seed >>> 0`.
- `step(state)` → a NEW state object (pure — must NOT mutate the input's
  `heat` or `prng`):
  - Bottom row (row `height-1`): each of the `width` cells = one PRNG value in
    `[0,1)`.
  - Each other row `r` from `height-2` down to `0`, each column `c`:
    `new[r][c] = clamp(((belowLeft + below + belowRight) / 3) * DECAY, 0, 1)`
    where `below = heat[(r+1)*width + c]`,
    `belowLeft = heat[(r+1)*width + max(0, c-1)]`,
    `belowRight = heat[(r+1)*width + min(width-1, c+1)]`.
  - `DECAY = 0.98`.
  - The returned state's `prng` = the PRNG state after consuming `width`
    values this step.
- PRNG: mulberry32 (32-bit integer state, outputs in `[0,1)`).

Built-in Node.js modules only. No npm packages.

## Tests (write FIRST — `tests/fire_model.test.js`, expect RED)

Use `node:test` + `node:assert/strict`. Cover:
1. **Shape:** `createModel()` returns `width=80`, `height=24`, `heat` a
   `Float64Array` of length `80*24` all zeros, and `prng` a number.
2. **Determinism:** two models with `seed=1337`, each stepped 50 times →
   identical `heat` (deep equal) and identical `prng`.
3. **Different seeds differ:** `seed=1` vs `seed=2`, each stepped 10 times →
   `heat` arrays differ.
4. **Purity:** copy `state.heat` and record `state.prng`; call `step(state)`;
   the original `state.heat` (every element) and `state.prng` are unchanged.
5. **Bounds / no NaN:** step a default model 200 times; every `heat` value is
   finite and within `[0,1]`.
6. **Rise:** step a default model 100 times; the top row (row 0) has at least
   one cell `> 0`.

## Verification

`bash scripts/run.sh test tests/fire_model.test.js` → all tests PASS.

## Deliverables

- `src/fire_model.js`
- `tests/fire_model.test.js`
- `docs/fire_model.md` (brief: what it does, the two exports, the step rule)

## Final report (STRICTLY ≤ 5 lines)
1. TASK: DONE
2. Files: src/fire_model.js, tests/fire_model.test.js, docs/fire_model.md
3. Tests: PASS
