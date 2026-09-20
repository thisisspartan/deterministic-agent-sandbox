# TASK-STANOK-CC-082 — Terminal fire (Node.js)

impl: src/fire.js
test: tests/fire.test.js
docs: docs/fire.md

Implement a realistic, beautiful burning flame rendered in the terminal.
Running `node src/fire.js` must show an animated fire; pressing Ctrl-C must
stop it cleanly (cursor restored, ANSI state reset, exit 0).

## Stack

Node.js, CommonJS, ZERO external dependencies (node built-ins only).
Match the project's existing stack — look at `scripts/run.sh` and the
existing test files before writing anything.

## Architecture (required — the animation must be testable headless)

`src/fire.js` is a single module with four separated concerns:

1. **Simulation (pure function(s))** — a 2D heat-field grid. Each tick:
   heat is injected at the base, diffuses upward, cools, and is perturbed
   by turbulence (value-noise or random walk). Use a SEEDED PRNG so frames
   are deterministic for tests. Heat values normalized to [0, 1].
2. **Palette (pure function)** — heat value → color via a multi-stop
   gradient: white-hot core → yellow → orange → red → dark red →
   transparent. Emit 24-bit truecolor ANSI (`\x1b[38;2;R;G;B m`).
   Zero heat → empty cell (plain space, no escape).
3. **Renderer (pure function)** — grid → one ANSI frame string. Use
   half-block (`▀`) or full-block characters for vertical resolution.
   Frame dimensions must match the grid.
4. **Loop (IO only)** — starts ONLY when run as main
   (`require.main === module` guard): hide the cursor, animate at
   ~30–60 FPS, clear the screen each frame, flame centered in
   `process.stdout.columns` x `process.stdout.rows` (fallback 80x24).
   On SIGINT: stop the interval, restore the cursor (`\x1b[?25h`),
   reset ANSI (`\x1b[0m`), exit 0.

## Realism features (all required)

- Flicker: global intensity noise per frame.
- Turbulence: per-cell perturbation so the flame sways and licks.
- Flame shape: wide base tapering upward — not a static cone.
- Glow: brighter core than edges (the gradient provides this).
- Smoke: faint gray particles rising above the flame.

## Test contract (`tests/fire.test.js` — your tests must assert these)

- Determinism: same seed → identical rendered frame string.
- Heat field: all values in [0, 1]; the field changes between two ticks.
- Palette: every RGB component in 0–255; a hot core maps brighter than a
  cool edge; zero heat → empty cell.
- Renderer: the frame string contains ANSI escape sequences; frame
  dimensions match the grid.
- `bash scripts/run.sh smoke src/fire.js` must load the module WITHOUT
  starting the animation (the main-guard above).

## Docs (`docs/fire.md`)

A few lines: how to run (`node src/fire.js`), how to stop (Ctrl-C),
how it works (heat field → palette → renderer), FPS.

## Notes

- Run your test with `bash scripts/run.sh test tests/fire.test.js`.
- Do not introduce a second language or test framework.

Final report (STRICTLY <= 5 lines):
1. TASK: DONE
2. Files: <list>
3. Tests: PASS
