# TASK-STANOK-CC-059 — Doom Fire: terminal app (animation loop) + docs

Status: `[ ] TODO`

Part 3 of 3 of the terminal 2D fire feature. `src/fire_model.js` (CC-057) and
`src/fire_render.js` (CC-058) already exist — do NOT modify them. This ticket
is the terminal front-end plus documentation.

## 1. Feature: `src/main.js`

CommonJS module, no external dependencies. Terminal animation of the fire.

### Structure (testable, headless-safe)
- `getTerminalSize()` — returns `{ columns, rows }`:
  - Reads `process.stdout.columns` / `process.stdout.rows` when available and
    > 0; otherwise falls back to `80 × 24`.
  - Must NEVER throw — headless / no-TTY environments (sandbox, piped stdout)
    must work.
- `createApp({ w, h, fps, maxHeat, seed, write })` — returns an app object:
  - `w`, `h` — grid size (defaults: `getTerminalSize()`).
  - `fps` — frames per second, default 25.
  - `write` — optional injectable function `write(string)` used to emit
    frames (default: `process.stdout.write`). Injectable so tests can capture
    output without a TTY.
  - `start()`:
    - If stdout is a TTY: emit alternate-screen `\033[?1049h` and hide-cursor
      `\033[?25l` once, before the first frame.
    - Runs the animation loop at `fps` via `setInterval` (or a `setTimeout`
      chain) — NO busy-loop. Each tick: `model.step()`, then
      `renderFrame(model.grid, { maxHeat })`, then write the frame (rows
      joined with `\n`, positioned at the top of the screen in TTY mode,
      e.g. `\033[H` prefix or clear-screen per frame — your choice).
    - In headless mode (stdout not a TTY): no terminal escapes, but the loop
      still runs and frames are still emitted via `write`. Must not crash.
  - `stop()`:
    - Stops the loop.
    - If stdout is a TTY: show cursor `\033[?25h`, leave alternate screen
      `\033[?1049l`, reset color `\033[0m`.
    - Must be idempotent — calling `stop()` twice must not throw.
- SIGINT: when run as a script, register `process.on('SIGINT', ...)` that
  calls `stop()` and exits with code 0.
- Entry point: when run directly (`require.main === module`), create the app
  with the terminal size, `start()`, register the SIGINT handler. When
  required as a module: NO side effects — no loop starts, nothing is written
  to stdout, no terminal escapes.

## 2. Tests: `tests/fire_app.test.js`

Run: `bash scripts/run.sh test tests/fire_app.test.js` (single-file mode).
Use `node:test` + `node:assert/strict` only. Cover at minimum:

- `getTerminalSize()` returns positive integers `{ columns, rows }` in the
  headless test environment (no TTY) and does not throw.
- `createApp({ w: 20, h: 10, fps: 60, write: captureFn })` — `start()` then
  `stop()` completes without error in headless mode.
- Frame production: with an injected `write` capture function, after
  `start()` at least one frame is written within ~500 ms; each frame, when
  split on `\n`, has exactly `h` rows.
- `stop()` is idempotent (calling it twice does not throw).
- No side effects on require: assert the exports (`getTerminalSize`,
  `createApp`) exist. Then verify require-time cleanliness in a SEPARATE
  child node process (NOT by patching `process.stdout.write` in the test
  process — node:test writes its own TAP/IPC protocol through that same
  function, which false-positives). Use `node:child_process`:
  `execFileSync(process.execPath, ['-e', "require('<absolute path to
  src/main.js>'); setTimeout(() => process.exit(0), 300);"])` and assert the
  child's stdout is empty (no frames, no terminal escapes).

Real assertions only — no empty tests.

## 3. Docs: `docs/fire.md`

Brief: what the fire is (Doom fire algorithm), the three modules
(`fire_model.js` — pure heat math, `fire_render.js` — heat→ANSI mapping,
`main.js` — terminal loop), how to run (`node src/main.js`), how to test
(`bash scripts/run.sh test tests/fire_model.test.js tests/fire_render.test.js
tests/fire_app.test.js`), terminal hygiene (alternate screen buffer, cursor
hide/show, color reset, SIGINT handling), and the headless fallback
(80×24 default, no escapes when stdout is not a TTY).

## 4. Acceptance criteria

- `bash scripts/run.sh test tests/fire_app.test.js` — all tests pass.
- `bash scripts/run.sh test tests/fire_model.test.js tests/fire_render.test.js`
  — still pass (no regressions).
- Files created: `src/main.js`, `tests/fire_app.test.js`, `docs/fire.md`
  (nothing else).
- No external dependencies, CommonJS only.
