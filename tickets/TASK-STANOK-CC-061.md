# TASK-STANOK-CC-061 — Doom Fire realism 1/3: temporal inertia + coherent turbulence (opt-in)

## Context
`src/fire_model.js` implements the classic Doom fire heat model:
`createFireModel(w, h, opts)` → `{ w, h, maxHeat, grid, step }`.
`grid[y][x]` is in `[0, maxHeat]`, `y = 0` is the TOP row, `y = h-1` is the BOTTOM row (heat source).
Current `opts`: `{ maxHeat=255, decay=0.08, seed }`. A self-contained xorshift32 PRNG (`rand()`)
drives all stochasticity. Current `step()`:
1. Bottom row: `next[h-1][x] = maxHeat * (0.7 + 0.3 * rand())`.
2. For `y = h-2 .. 0`: pick `dx ∈ {-1,0,1}` via `rand()`, read `below = grid[y+1][nx]` (old state,
   clamped x), then `v = below - decay * rand() * maxHeat`, clamp to `[0, maxHeat]`, write `next[y][x]`.
3. Commit `next` into `grid`.

**The realism gap:** every cell is computed purely from the row below with independent per-cell white
noise. There is (a) no temporal inertia — a cell has no memory of its own previous value, so the flame
is grainy noise rather than coherent tongues; and (b) no coherent turbulence — the jitter is independent
per cell, so there are no smooth rising plumes.

## Task
Add TWO opt-in realism options to `createFireModel`. **Both default to `0`, and with both `0` the
behavior must be BIT-IDENTICAL to the current legacy algorithm** (same PRNG call order, same values).
All existing tests in `tests/fire_model.test.js` use default opts and MUST keep passing unchanged.

### New options
- `inertia`: number in `[0, 1)`, default `0`. Blends a cell's own previous value into the new value
  (temporal smoothing → coherent tongues).
- `turbulence`: number in `[0, 1]`, default `0`. Adds a coherent, slowly time-evolving noise field
  (smooth in space, drifting in time) so heat rises in plumes instead of uniform decay.

Validation (throw `TypeError` otherwise):
- `inertia`, if provided, must be a finite number in `[0, 1)`.
- `turbulence`, if provided, must be a finite number in `[0, 1]`.

### Reference algorithm (deterministic — implement exactly this so determinism holds)
Use the SAME single PRNG stream (`rand`) as today. Coarse turbulence field:
- `tw = max(1, ceil(w / 4))`, `th = max(1, ceil(h / 4))`.
- Field is a `th × tw` array, every cell initialized to `0.5`.

`step()`:
1. **Turbulence field update — ONLY if `turbulence > 0`:** for each coarse cell `(cy, cx)`:
   `field[cy][cx] = clamp(field[cy][cx] + (rand() - 0.5) * 0.1, 0, 1)`.
   (This consumes `tw*th` `rand()` calls; when `turbulence === 0` it is skipped entirely, preserving
   the legacy PRNG call order.)
2. **Bottom row (unchanged):** `next[h-1][x] = maxHeat * (0.7 + 0.3 * rand())`.
3. **For `y = h-2 .. 0`, each `x`:**
   - `dx = DX[floor(rand()*3)]`; `nx = clamp(x + dx, 0, w-1)`.
   - `below = grid[y+1][nx]` (old state).
   - `v = below - decay * rand() * maxHeat`.
   - **If `turbulence > 0`:** `cx = min(tw-1, floor(x * tw / w))`, `cy = min(th-1, floor(y * th / h))`;
     `v += turbulence * (field[cy][cx] - 0.5) * 0.5 * maxHeat`.
   - **If `inertia > 0`:** `v = inertia * grid[y][x] + (1 - inertia) * v`  (`grid[y][x]` is the OLD value).
   - Clamp `v` to `[0, maxHeat]`; `next[y][x] = v`.
4. Commit `next` into `grid`.

With `inertia = 0` and `turbulence = 0`, steps 1, the turbulence add, and the inertia blend are all
skipped → `v = below - decay * rand() * maxHeat`, clamped — exactly the legacy algorithm.

The returned object stays `{ w, h, maxHeat, grid, step }` (do not add new exported fields).

## Tests (extend `tests/fire_model.test.js`; do NOT delete or weaken any existing test)
Add tests covering:
1. **Legacy identity (default opts):** with NO `inertia`/`turbulence` opts, a small grid (e.g. `5×5`,
   `seed: 1`) after exactly 1 `step()` must equal the output of an inline reference legacy
   implementation written inside the test (bottom row `maxHeat*(0.7+0.3*rand)`, upper rows
   `below - decay*rand*maxHeat` with the same xorshift32 and dx order). This pins bit-identical
   default behavior.
2. **Determinism with new opts:** two models, same `seed`, `opts { inertia: 0.5, turbulence: 0.5 }`,
   50 `step()`s → `deepStrictEqual` grids.
3. **Range with new opts:** a model with `{ inertia: 0.5, turbulence: 0.5 }`, 100 `step()`s → every
   cell in `[0, maxHeat]` (reuse the existing `assertInRange` helper).
4. **Inertia smooths frame-to-frame change:** fixed `seed`, `w=40, h=24`. Model A `{ inertia: 0 }`,
   model B `{ inertia: 0.5 }`, both `turbulence: 0`, same seed. Run 200 warmup `step()`s, then over the
   next 50 frames compute the mean absolute per-cell change between consecutive frames. Assert
   `meanDelta(B) < meanDelta(A)`.
5. **Turbulence extends the flame upward:** fixed `seed`, `w=40, h=24`. Model A `{ turbulence: 0 }`,
   model B `{ turbulence: 0.5 }`, both `inertia: 0`, same seed. Run 200 warmup `step()`s. Let
   `topThirdMax(m)` = max cell value over rows `y` in `[0, floor(h/3))`. Assert
   `topThirdMax(B) > topThirdMax(A)` and `topThirdMax(B) > 0`.
6. **Invalid opts throw `TypeError`:** `inertia: 1.0`, `inertia: -0.1`, `inertia: 'x'`,
   `turbulence: 1.5`, `turbulence: -0.1`, `turbulence: null` → each throws `TypeError`.

## Constraints
- Work only in `src/fire_model.js`, `tests/fire_model.test.js`, `docs/fire.md`.
- Do NOT touch any other test file (the TDD gate locks all other tests). Do not delete existing tests.
- Pure module: no I/O, no new dependencies, built-in Node only.
- Update `docs/fire.md` to document the two new options and their defaults (a short paragraph is
  enough; keep the existing content).
