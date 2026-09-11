# TASK-STANOK-CC-073 — Fire renderer (ansi256 + symbols)

## Contract

Create `src/fire_render.js` exporting:

- `renderFrame(state, {mode='ansi256'})` → string.
  - `state` is a model state `{width, height, heat}` (a `Float64Array`,
    row-major, row 0 = top).
  - Returns `height` lines joined by `\n`, NO trailing newline. Row 0 (top) =
    first line.
  - **ansi256** (default): each cell = `'\x1b[38;2;r;g;bm' + '█'` where
    `(r,g,b) = ramp(heat)` with each channel rounded to the nearest integer.
  - **symbols**: each cell = exactly one character, NO escape sequences:
    `0 → ' '`, `(0,0.25] → '░'`, `(0.25,0.5] → '▒'`, `(0.5,0.75] → '▓'`,
    `(0.75,1] → '█'`.
- `ramp(h)` for `h` in `[0,1]`: piecewise-linear interpolation over the stops
  `0→(0,0,0)`, `0.25→(128,0,0)`, `0.5→(255,64,0)`, `0.75→(255,160,0)`,
  `1→(255,255,255)`.

Pure and deterministic. `renderFrame` only reads `state.heat/width/height` — it
must not require or mutate the model. Built-in Node.js modules only.

## Tests (write FIRST — `tests/fire_render.test.js`, expect RED)

Use `node:test` + `node:assert/strict`. Build small model states by hand
(e.g. `width=4, height=3`, `heat` a `Float64Array`) — keep the test
self-contained, do NOT depend on `src/fire_model.js`. Cover:
1. **Dimensions (symbols):** output has exactly `height` lines; each line has
   exactly `width` characters.
2. **Zero state (ansi256):** all-zero `heat` → every cell escape is
   `'\x1b[38;2;0;0;0m'`.
3. **Max state (ansi256):** all-`1.0` `heat` → every cell escape is
   `'\x1b[38;2;255;255;255m'` and the visible char is `'█'`.
4. **Midpoint (ansi256):** a cell with `heat=0.5` → escape
   `'\x1b[38;2;255;64;0m'`.
5. **Symbols mapping:** `heat 0→' '`, `0.25→'░'`, `0.5→'▒'`, `0.75→'▓'`,
   `1.0→'█'`; the symbols output contains NO `'\x1b'`.
6. **Determinism:** `renderFrame(state)` called twice → identical string.

## Verification

`bash scripts/run.sh test tests/fire_render.test.js` → all tests PASS.

## Deliverables

- `src/fire_render.js`
- `tests/fire_render.test.js`
- `docs/fire_render.md` (brief: the two modes, the ramp stops, the symbol map)

## Final report (STRICTLY ≤ 5 lines)
1. TASK: DONE
2. Files: src/fire_render.js, tests/fire_render.test.js, docs/fire_render.md
3. Tests: PASS
