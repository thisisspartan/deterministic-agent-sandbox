# TASK-STANOK-CC-057 — Doom Fire: heat model (pure logic)

Status: `[ ] TODO`

Part 1 of 3 of the terminal 2D fire feature. This ticket is ONLY the pure
mathematical model — no terminal, no I/O, fully testable headless.

## 1. Feature: `src/fire_model.js`

CommonJS module, no external dependencies (self-contained), exports exactly
one function:

### `createFireModel(w, h, opts)`
- `w`, `h`: positive integers — grid width/height in cells.
  Throws `TypeError` if either is not a positive integer (0, negatives,
  fractions, strings, null, undefined).
- `opts` (optional object):
  - `maxHeat` — positive number, default `255`.
  - `decay` — number in `(0, 1]`, default `0.08` — random decay coefficient.
  - `seed` — non-negative integer, optional. If given, the internal PRNG is
    seeded (fully deterministic). If absent, a random seed is used.
- Returns a model object:
  - `w`, `h`, `maxHeat` — numbers.
  - `grid` — 2D array `grid[y][x]`, `y = 0` is the TOP row, `y = h-1` is the
    BOTTOM row (the heat source). All values are numbers in `[0, maxHeat]`.
  - `step()` — advances the simulation by one frame:
    1. Bottom row (`y = h-1`): each cell gets stochastic heat
       `maxHeat * (0.7 + 0.3 * rand())` — values in `[0.7*maxHeat, maxHeat]`,
       varying between cells.
    2. Every cell `(x, y)` for `y < h-1`:
       `newTemp = max(0, below - decay * rand() * maxHeat)` where
       `below = grid[y+1][x + dx]`, `dx ∈ {-1, 0, 1}` is a random jitter,
       and `x + dx` is clamped to `[0, w-1]`.
    3. All values are clamped to `[0, maxHeat]`.
    The update must be applied to a new state (a cell must not read a value
    that was already updated this frame).
- The module must be pure: no I/O, no terminal calls, no side effects other
  than mutating its own `grid`.
- The PRNG must be self-contained and deterministic (e.g. mulberry32).

## 2. Tests: `tests/fire_model.test.js`

Run: `bash scripts/run.sh test tests/fire_model.test.js` (single-file mode).
Use `node:test` + `node:assert/strict` only. Cover at minimum:

- `createFireModel(80, 24)` → `grid` has 24 rows of 80 numbers, all in `[0, 255]`.
- Range invariant: after 100 `step()` calls on a 200×60 grid, every value is
  still in `[0, maxHeat]`.
- Bottom row: after `step()`, every bottom-row value is in
  `[0.7*maxHeat, maxHeat]`, and (for `w >= 2`) at least two distinct values
  exist in the bottom row.
- Heat cannot exceed the row below: after `step()`, for every `y < h-1` and
  every `x`, `grid[y][x] <= max(grid[y+1])`.
- Monotonic decay: with a fixed seed, after >= 200 warm-up steps on an 80×24
  grid, the average temperature of each row is strictly less than the average
  of the row directly below it (bottom to top).
- Stochasticity: two models with different seeds have different grids after
  10 steps; consecutive `step()` calls change the grid (at least one cell
  differs).
- Determinism: two models created with the same seed produce identical grids
  (deep equal) after 50 steps.
- Custom `maxHeat` (e.g. 100): all values stay in `[0, 100]`.
- Boundaries: 3×3 grid steps without error and stays in range; 200×60 works;
  1×1 grid works (bottom row is also the top row, values stay in range).
- Throws `TypeError` for: (0, 24), (80, 0), (-5, 24), (80.5, 24), ("80", 24),
  (null, 24), (undefined, 24).

Real assertions only — no empty tests.

## 3. Acceptance criteria

- `bash scripts/run.sh test tests/fire_model.test.js` — all tests pass.
- Files created: `src/fire_model.js`, `tests/fire_model.test.js` (nothing else).
- No external dependencies, CommonJS only, zero I/O in the module.
