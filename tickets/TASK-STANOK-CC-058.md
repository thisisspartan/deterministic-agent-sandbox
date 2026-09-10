# TASK-STANOK-CC-058 — Doom Fire: renderer (heat grid → ANSI frame)

Status: `[ ] TODO`

Part 2 of 3 of the terminal 2D fire feature. `src/fire_model.js` already
exists (CC-057) — do NOT modify it. This ticket is ONLY the renderer: a pure
mapping from a temperature matrix to a string frame buffer.

Do not touch any existing test file other than
`tests/fire_render.test.js` (the TDD gate locks all other tests).

## 1. Feature: `src/fire_render.js`

CommonJS module, no external dependencies, exports:

### `renderFrame(grid, opts)`
- `grid`: 2D array `grid[y][x]` of numbers in `[0, maxHeat]`, `y = 0` is the
  TOP row.
- `opts` (optional object):
  - `maxHeat` — positive number, default `255`.
  - `palette` — `"ansi256"` (default) or `"symbols"`.
- Returns: an array of `h` strings (one per row, top first). Each row renders
  exactly `w` visible characters (ANSI escape sequences do not count as
  visible characters).
- Cell mapping:
  - `ansi256`: temperature 0 → a space (cold/background). Temperature > 0 →
    a block character (e.g. `█`) wrapped in an ANSI 256-color escape
    `\033[38;5;<n>m` (and a reset `\033[0m` if you use one per cell), where the
    palette index `<n>` is monotonically non-decreasing in temperature:
    index for 0 is the darkest, index for `maxHeat` is the hottest (bright
    white / red-hot end of the palette).
  - `symbols`: NO ANSI escapes. Temperature 0 → space. Temperature > 0 → one
    of the gradient symbols `░▒▓█` chosen monotonically: colder → `░`,
    hottest → `█`.
- The function must be pure: no I/O, no terminal calls.

### `PALETTE`
- Exported constant: the temperature→color mapping used by `renderFrame`
  (e.g. an array of 256 ANSI-256 indices, or the symbols table) — exported so
  tests can inspect the mapping directly.

## 2. Tests: `tests/fire_render.test.js`

Run: `bash scripts/run.sh test tests/fire_render.test.js` (single-file mode).
Use `node:test` + `node:assert/strict` only. Cover at minimum:

- Cold frame: a 10×5 grid of all zeros → 5 rows, each exactly 10 visible
  characters, no visible non-space characters.
- Hot frame (ansi256): a 10×5 grid of all `maxHeat` → every cell contains an
  ANSI escape `\033[38;5;<n>m` and the index `<n>` equals the hottest palette
  index.
- Monotonicity: for temperatures `0 < t1 < t2 <= maxHeat` sufficiently far
  apart, the palette index for `t2` is strictly greater than for `t1`
  (check via `PALETTE` or by parsing the escapes).
- Symbols mode: output contains only characters from the set ` ░▒▓█` (no
  `\033` anywhere); cold cells are spaces, hottest cells are `█`.
- Dimensions: for a 200×60 grid, the output has exactly 60 rows and each row
  has exactly 200 visible characters (strip ANSI escapes before measuring).
- Throws `TypeError` if `grid` is not an array of arrays of numbers
  (e.g. `null`, `"abc"`, `[[1, "x"]]`, `[1, 2]`).

Real assertions only — no empty tests.

## 3. Acceptance criteria

- `bash scripts/run.sh test tests/fire_render.test.js` — all tests pass.
- Files created: `src/fire_render.js`, `tests/fire_render.test.js` (nothing else).
- No external dependencies, CommonJS only, zero I/O in the module.
