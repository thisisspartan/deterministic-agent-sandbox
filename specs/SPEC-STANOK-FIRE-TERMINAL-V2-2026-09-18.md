# SPEC — Realistic terminal fire (V2), 2026-09-18

Ticket: `tickets/TASK-STANOK-CC-078.md`. Stack: Node.js (project's existing
stack, `scripts/run.sh` contract), zero external dependencies.

## Goal

A maximally realistic, beautiful burning flame rendered in the terminal:
`node src/fire.js` → animated fire; Ctrl-C → clean stop (cursor restored,
ANSI state reset, exit 0).

## Architecture (required — keeps the animation testable headless)

`src/fire.js` is a single CommonJS module with four separated concerns:

1. **Simulation (pure)** — 2D heat-field grid. Per tick: heat injected at
   the base, diffuses upward, cools, and is perturbed by turbulence
   (value-noise / random walk). Seeded PRNG → deterministic frames for tests.
   Heat values normalized to [0, 1].
2. **Palette (pure)** — heat → color via a multi-stop gradient:
   white-hot core → yellow → orange → red → dark red → transparent.
   24-bit truecolor ANSI (`\x1b[38;2;R;G;B m`). Zero heat → no cell (space).
3. **Renderer (pure)** — grid → one ANSI frame string (half-block `▀` or
   full-block chars for vertical resolution; dimensions match the grid).
4. **Loop (IO only)** — starts ONLY when run as main
   (`require.main === module`): hides cursor, ~30–60 FPS interval,
   clears screen per frame, flame centered in `stdout.columns/rows`
   (fallback 80x24). SIGINT handler: stop interval, restore cursor
   (`\x1b[?25h`), reset ANSI (`\x1b[0m`), exit 0.

## Realism features (all required)

- Flicker: global intensity noise per frame.
- Turbulence: per-cell perturbation so the flame sways and licks.
- Flame shape: wide base tapering upward, not a static cone.
- Glow: brighter core than edges (gradient handles it).
- Smoke: faint gray particles rising above the flame.

## Test contract (`tests/fire.test.js`)

- Determinism: same seed → identical frame string.
- Heat field: values in [0,1]; field changes between ticks.
- Palette: RGB components in 0–255; core hotter than edge; zero heat → empty.
- Renderer: frame contains ANSI escapes; dimensions match the grid.
- `scripts/run.sh smoke src/fire.js` loads the module WITHOUT starting the
  animation (main-guard).

## Acceptance (supervisor)

- rc=0, verifier=PASS, honest run (code was cleaned — no pre-existing).
- Operator manual check: `node src/fire.js` in a real terminal — realistic
  flame, Ctrl-C clean stop.
