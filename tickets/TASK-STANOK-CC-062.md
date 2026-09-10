# TASK-STANOK-CC-062 — Doom Fire realism 2/3: glyph-density soft edges in ansi256 (opt-in)

## Context
`src/fire_render.js` maps a heat grid to an ANSI frame buffer:
`renderFrame(grid, opts)` → `h` row strings (one per row, top first), each with exactly `w` VISIBLE
characters (ANSI escapes are not visible characters).
Current `opts`: `{ maxHeat=255, palette='ansi256'|'symbols' }`.
- `t <= 0` → a space.
- `palette: 'ansi256'` → every hot cell is rendered as `\u001b[38;5;<n>m█\u001b[0m` where
  `n = PALETTE[tempToPos(t, maxHeat)]` (a 256-entry black→red→orange→yellow→white ramp). **Every hot
  cell uses the same `█` glyph; only the color varies.**
- `palette: 'symbols'` → `SYMBOLS[level]` where `SYMBOLS = ['░','▒','▓','█']` and
  `level = min(3, floor(tempToPos(t, maxHeat) / 255 * 4))`; no ANSI escapes.
- `tempToPos(t, maxHeat) = clamp(round(t / maxHeat * 255), 0, 255)`.

**The realism gap:** in `ansi256` mode every hot cell is a solid `█`, so the flame has hard, blocky
edges. Real fire has soft, feathered edges (dim, sparse) around a bright, dense core. Encoding
brightness into the GLYPH DENSITY as well as the color gives soft edges + a bright core.

## Task
Add ONE opt-in option `density` (boolean, default `false`) to `renderFrame`. **With `density`
absent/`false`, behavior is bit-identical to today** and all existing tests in
`tests/fire_render.test.js` MUST keep passing unchanged.

### Behavior
- `density` only applies when `palette === 'ansi256'`. For `palette: 'symbols'`, `density` is ignored
  (symbols mode already uses glyph density).
- When `density === true` and `palette === 'ansi256'` and `t > 0`:
  - `pos = tempToPos(t, maxHeat)`.
  - `level = min(3, floor(pos / 255 * 4))`  (same formula symbols mode uses).
  - `n = PALETTE[pos]`.
  - emit `\u001b[38;5;<n>m` + `SYMBOLS[level]` + `\u001b[0m`.
  So a cold hot-cell renders as a dim `░`/`▒`, a hot cell as a bright `█` — soft edges, bright core.
- `t <= 0` → space (unchanged). `density === false` (default) → unchanged `█` for every hot cell.

Validation: if `density` is provided it must be a boolean, else throw `TypeError`.

The exported surface stays `{ renderFrame, PALETTE, SYMBOLS }`.

## Tests (extend `tests/fire_render.test.js`; do NOT delete or weaken any existing test)
Add tests covering:
1. **density=true ansi256 maps heat to glyph density:** a `2×1` grid `[[10], [250]]`, `maxHeat: 255`,
   `density: true`, `palette: 'ansi256'`. Strip ANSI (reuse the existing `visible()` helper). Assert the
   cold cell's visible glyph is `░` (`level 0`) and the hot cell's visible glyph is `█` (`level 3`).
   Assert each row still contains exactly one `\u001b[38;5;<n>m` color escape (reuse `ansiIndices()`).
2. **density=true keeps color monotonic:** hotter cell carries a strictly greater ANSI index than a
   much colder cell (reuse `ansiIndices()`), same as the existing monotonicity test but with
   `density: true`.
3. **density=false (default) ansi256 uses `█` for every hot cell:** a mixed-heat grid rendered with
   default opts → every hot visible char is `█` (this is today's behavior; pin it explicitly).
4. **density=true: row length is still `w` visible chars** (ANSI stripped) for a non-trivial grid.
5. **density=true with `palette: 'symbols'` is unchanged:** no ANSI escapes, glyphs only from
   ` ░▒▓█` (density must not add color in symbols mode).
6. **Invalid `density` throws `TypeError`:** `density: 1`, `density: 'true'`, `density: null` →
   each throws `TypeError`.

## Constraints
- Work only in `src/fire_render.js`, `tests/fire_render.test.js`, `docs/fire.md`.
- Do NOT touch any other test file (the TDD gate locks all other tests). Do not delete existing tests.
- Pure module: no I/O, no new dependencies, built-in Node only.
- Update `docs/fire.md` to document the new `density` option (a short paragraph; keep existing content).
