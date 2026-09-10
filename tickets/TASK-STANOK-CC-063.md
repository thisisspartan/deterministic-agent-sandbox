# TASK-STANOK-CC-063 — Doom Fire realism 3/3: wire realism options into the app + docs

## Context
`src/main.js` is the terminal front-end. `createApp(opts)` composes the two pure modules:
- `createFireModel(w, h, modelOpts)` from `src/fire_model.js` — now also accepts opt-in
  `inertia` (default `0`) and `turbulence` (default `0`) (added by CC-061).
- `renderFrame(grid, renderOpts)` from `src/fire_render.js` — now also accepts opt-in
  `density` (boolean, default `false`) (added by CC-062).

Current `createApp(opts)` accepts `{ w, h, fps=25, maxHeat, seed, write }`. It:
- defaults `w`/`h` from `getTerminalSize()` (80×24 headless fallback), `fps` to 25.
- builds `modelOpts` from `maxHeat`/`seed` only.
- in `tick()`: `model.step()`, then `renderFrame(model.grid, { maxHeat, palette: tty ? 'ansi256' : 'symbols' })`,
  then `write((tty ? HOME : '') + rows.join('\n'))`.
- returns `{ w, h, fps, maxHeat, start, stop }`.
- Headless (non-TTY) uses the escape-free `symbols` palette; TTY uses `ansi256`.
- Requiring the module has no side effects (no loop, no output); the entry point runs only when
  executed directly (`require.main === module`).

**Goal:** make the DEFAULT app render the more realistic fire (coherent tongues + soft edges) by
wiring the new realism options through, with sensible realistic defaults, while keeping every existing
`tests/fire_app.test.js` test passing.

## Task
1. **New `createApp` options** (all with realistic defaults):
   - `inertia` — default `0.5`, forwarded to `modelOpts.inertia`.
   - `turbulence` — default `0.5`, forwarded to `modelOpts.turbulence`.
   - `density` — default `true`, forwarded to the `renderFrame` opts as `density`.
   Each may be overridden by the caller.
2. **Forward them:** in `createApp`, set `modelOpts.inertia` and `modelOpts.turbulence` from the
   (defaulted) values, and pass `density` into the `renderFrame(...)` call in `tick()`.
   `density` only affects `ansi256` (TTY) mode; in headless `symbols` mode it is ignored by the
   renderer — that is fine and expected.
3. **Expose on the returned object:** add `inertia`, `turbulence`, `density` to the object returned by
   `createApp` (alongside `w, h, fps, maxHeat, start, stop`) so the defaults/overrides are observable.
4. **Keep everything else identical:** terminal hygiene, SIGINT, headless fallback, no-side-effects-on-
   require, entry point — all unchanged.

## Tests (extend `tests/fire_app.test.js`; do NOT delete or weaken any existing test)
Add tests covering:
1. **Realistic defaults:** `createApp({ write: () => {} })` → `app.inertia === 0.5`,
   `app.turbulence === 0.5`, `app.density === true`.
2. **Overrides are honored:** `createApp({ inertia: 0, turbulence: 0, density: false, write: () => {} })`
   → `app.inertia === 0`, `app.turbulence === 0`, `app.density === false`.
3. **Headless frames stay clean under the realistic defaults:** `createApp({ w: 20, h: 10, fps: 60,
   seed: 5, write: (s) => frames.push(String(s)) })`, `start()`, wait ~200 ms, `stop()`. Assert at least
   one frame, each frame splits into exactly `h` rows, and NO frame contains `\u001b[` (headless uses the
   escape-free symbols palette even with the new defaults).
4. **Existing require-cleanliness and idempotency tests must still pass** (do not modify them).

## Constraints
- Work only in `src/main.js`, `tests/fire_app.test.js`, `docs/fire.md`.
- Do NOT touch any other test file (the TDD gate locks all other tests). Do not delete existing tests.
- No new dependencies, built-in Node only.
- Update `docs/fire.md`: document the three new app options and their realistic defaults
   (`inertia=0.5`, `turbulence=0.5`, `density=true`), and note that headless mode still uses the
   escape-free symbols palette. Keep the existing content.
