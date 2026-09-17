# TASK-STANOK-CC-076 — Terminal fire: infinite Doom-style animation

module: fire

Build an infinite terminal fire animation (classic Doom-fire effect). The operator
launches it in a real terminal and stops it with Ctrl-C. Everything lives in ONE
module file `src/fire.js` (model + renderer + app + entry point).

## Contract (exact — tests assert these)

### Heat model (pure, deterministic)
- Grid `cols × rows` of integer heat, `0..MAX_HEAT`, `MAX_HEAT = 255`.
- PRNG: mulberry32 — `function mulberry32(seed) { return function() { seed |= 0; seed = seed + 0x6D2B79F5 | 0; let t = Math.imul(seed ^ seed >>> 15, 1 | seed); t = t + Math.imul(t ^ t >>> 7, 61 | t) ^ t; return ((t ^ t >>> 14) >>> 0) / 4294967296; }; }`
- `createModel(cols, rows, seed)` → `{ cols, rows, grid, rand }` where `grid` is a
  2D array (row 0 = top, row rows-1 = bottom), initially all 0.
- `step(model)` mutates the grid, one frame:
  1. bottom row: `grid[rows-1][x] = floor(rand() * 256)` (0..255).
  2. every other cell (top to bottom-1):
     `grid[y][x] = max(0, floor((grid[y][x-1] + grid[y][x+1] + grid[y+1][x] + grid[y][x]) / 4) - 1)`
     with out-of-range left/right neighbors treated as 0. `LOSS = 1`.
  3. result always clamped to `0..255`.
- Determinism: two models with the same seed produce identical grids after N steps.

### Renderer
- `renderFrame(model)` → array of `rows` strings; each string is exactly `cols`
  cells; each cell is one ANSI-256 escape `\x1b[38;5;<n>m` + one visible glyph
  (use `█`). Color index `n` from a 256-ramp: heat 0 → 0 (black), heat 255 → 255;
  the ramp must pass through red (~196), orange (~208), yellow (~220), white (~230)
  — a simple monotonic heat→index mapping is fine as long as it is monotonic
  and covers 0..255.
- No trailing newlines inside the returned array (the app joins with `\n`).

### App (`createApp` + `main`)
- `main()` entry: `cols = parseInt(process.env.COLUMNS || 80)`,
  `rows = parseInt(process.env.LINES || 24)`, `seed = parseInt(process.env.FIRE_SEED || 42)`.
- **TTY mode** (`process.stdout.isTTY`): write `\x1b[?1049h` (alt screen) +
  `\x1b[?25l` (hide cursor); loop at ~25 FPS (40 ms) rendering each frame to the
  home position (`\x1b[H`); on `SIGINT`: write `\x1b[?25h` + `\x1b[?1049h`,
  `process.exit(0)`.
- **Headless mode** (stdout NOT a TTY): render exactly 10 frames (join rows with
  `\n`, one `\n` per frame) to stdout, then `process.exit(0)`. No alt-screen
  escapes in headless mode. This MUST finish well under 10 seconds.
- Guard: only run `main()` when executed directly (`require.main === module`).

## Deliverables
1. `tests/fire.test.js` — write FIRST (red phase expected). node:test +
   node:assert/strict, built-ins only, no real-time waits, no network. Cover at
   least:
   - determinism: same seed, 5 steps → deep-equal grids; different seeds → grids differ.
   - clamp: after 50 steps every cell is an integer in 0..255.
   - decay: a single hot cell in an otherwise cold grid cools toward 0 over steps
     (with bottom row refilled, test an interior cell's neighborhood instead, or
     zero the bottom row after each step in the test).
   - renderer: `renderFrame` returns `rows` strings, each exactly `cols` cells
     (count visible glyphs), each cell matches `^\x1b\[38;5;\d+m█$`.
   - headless frame count is not testable here (app-level) — skip.
2. `src/fire.js` — implementation per the contract above.
3. `docs/fire.md` — one short paragraph: how to run (`node src/fire.js`),
   Ctrl-C stops it, env vars `COLUMNS`/`LINES`/`FIRE_SEED`.

## Verification
```
bash scripts/run.sh test tests/fire.test.js
bash scripts/run.sh smoke src/fire.js
```
The smoke run executes headless (stdin=/dev/null, 10s timeout): it must print
10 frames and exit 0.

Final report (STRICTLY <= 5 lines):
1. TASK: DONE
2. Files: src/fire.js, tests/fire.test.js, docs/fire.md
3. Tests: PASS
