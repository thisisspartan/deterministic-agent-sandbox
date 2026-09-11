# SPEC-fire-console — Console 2D terminal fire

A 2D fire simulation rendered in the terminal. It burns forever (infinite
loop) and exits cleanly on Ctrl+C (SIGINT) / SIGTERM. Deterministic: the same
seed reproduces the same fire frame-for-frame.

## Requirements

1. **Infinite burn (TTY):** when stdout is a TTY, the app enters the terminal
   alternate screen, hides the cursor, and renders the fire at 25 FPS forever.
   On SIGINT or SIGTERM it restores the terminal (show cursor, leave
   alternate screen) and exits with code 0.
2. **Headless:** when stdout is not a TTY or `STANOK_HEADLESS=1`, the app
   renders `FIRE_FRAMES` frames in symbols mode (no escape codes), separated
   by a blank line, paced at `FIRE_FPS`, then exits 0. SIGINT/SIGTERM exits 0
   early.
3. **Deterministic:** the simulation is driven by a seeded PRNG. Same seed →
   identical heat field every frame.
4. **No dependencies:** Node.js built-ins only (`node:test`,
   `node:assert/strict`, `node:child_process`). No npm packages.

## Design

Flat layout (machine convention `src/<module>.js`, `tests/<module>.test.js`,
`docs/<module>.md`):

- `src/fire_model.js` — heat simulation (Doom-fire model).
- `src/fire_render.js` — frame renderer (ansi256 + symbols).
- `src/main.js` — app entry (TTY infinite loop / headless, signal handling).
- `tests/fire_model.test.js`, `tests/fire_render.test.js`,
  `tests/fire_app.test.js`.
- `docs/fire_model.md`, `docs/fire_render.md`, `docs/main.md`.

### Model (`src/fire_model.js`)

- `createModel({width=80, height=24, seed=1337})` →
  `{ width, height, heat: Float64Array(width*height), prng: number }`.
  Row-major, row 0 = top. `heat` all zeros. `prng = seed >>> 0`.
- `step(state)` → new state (pure, does not mutate the input):
  - Bottom row (row `height-1`): each cell = one PRNG value in `[0,1)`.
  - Each other row `r` (from `height-2` down to `0`), each column `c`:
    `new[r][c] = clamp(((belowLeft + below + belowRight) / 3) * DECAY, 0, 1)`
    where `below = heat[(r+1)*width + c]`,
    `belowLeft = heat[(r+1)*width + max(0, c-1)]`,
    `belowRight = heat[(r+1)*width + min(width-1, c+1)]`.
  - `DECAY = 0.98`.
  - `prng` in the returned state = state after consuming `width` PRNG values.
- PRNG: mulberry32 (32-bit integer state, outputs in `[0,1)`).

### Renderer (`src/fire_render.js`)

- `renderFrame(state, {mode='ansi256'})` → string.
  - `height` lines joined by `\n`, no trailing newline. Row 0 (top) = first
    line.
  - **ansi256:** each cell = `'\x1b[38;2;r;g;bm' + '█'`, where `(r,g,b) =
    ramp(heat)` (each channel rounded to the nearest integer).
  - **symbols:** each cell = one char, no escapes:
    `0 → ' '`, `(0,0.25] → '░'`, `(0.25,0.5] → '▒'`, `(0.5,0.75] → '▓'`,
    `(0.75,1] → '█'`.
- `ramp(h)`: piecewise-linear over stops
  `0→(0,0,0)`, `0.25→(128,0,0)`, `0.5→(255,64,0)`, `0.75→(255,160,0)`,
  `1→(255,255,255)`.

### App (`src/main.js`)

- Entry: `node src/main.js`. Runs only when `require.main === module`.
- Env: `FIRE_SEED` (1337), `FIRE_FPS` (25), `FIRE_FRAMES` (50),
  `STANOK_HEADLESS` (`'1'` → headless).
- Headless when `STANOK_HEADLESS === '1'` or `!process.stdout.isTTY`.
- **TTY mode:** write `enterTerminal()`; loop forever: `step`, render ansi256,
  write `'\x1b[H' + frame`; sleep `1000/FIRE_FPS` ms. On SIGINT/SIGTERM: write
  `leaveTerminal()`, `process.exit(0)`.
- **Headless mode:** loop `FIRE_FRAMES`: `step`, render symbols, write
  `frame + '\n\n'`; sleep `1000/FIRE_FPS` ms. Then `process.exit(0)`.
  SIGINT/SIGTERM → `process.exit(0)`.
- Exports: `enterTerminal()` → `'\x1b[?1049h\x1b[?25l'`,
  `leaveTerminal()` → `'\x1b[?25h\x1b[?1049l'`.

## Acceptance

- `tests/fire_model.test.js`, `tests/fire_render.test.js`,
  `tests/fire_app.test.js` all PASS via `bash scripts/run.sh test <file>`.
- TTY: infinite 25 FPS fire; Ctrl+C restores terminal + exit 0.
- Headless: N symbols frames, no escapes, exit 0; SIGINT exits 0 early.
- Deterministic: same seed → identical output.

## Tickets

| Ticket | Scope |
|---|---|
| CC-072 | `src/fire_model.js` + `tests/fire_model.test.js` + `docs/fire_model.md` |
| CC-073 | `src/fire_render.js` + `tests/fire_render.test.js` + `docs/fire_render.md` |
| CC-074 | `src/main.js` + `tests/fire_app.test.js` + `docs/main.md` |
