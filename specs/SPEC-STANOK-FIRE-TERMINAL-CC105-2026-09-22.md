# SPEC — Realistic terminal fire (Python, post-clean honest run), 2026-09-22

Ticket: `tickets/TASK-STANOK-CC-105.md`. Stack: Python 3.11 stdlib, ZERO
external dependencies. The repo was cleaned to infra-only (src/tests/docs
empty) — this is an honest run, no pre-existing code.

## Goal

A maximally realistic, MULTICOLORED burning flame rendered in the terminal:
`python3 src/fire_color.py` → animated fire; Ctrl-C → clean stop (cursor
restored, ANSI state reset, exit 0). A real flame is not monochrome: blue
combustion base, white-hot core, yellow/orange body, red tips, faint gray
smoke above — all color families must appear natively (24-bit truecolor
ANSI, no terminal extensions).

## Architecture (required — keeps the animation testable headless)

`src/fire_color.py` is a single module with four separated concerns:

1. **Simulation (pure)** — 2D heat-field grid. Per tick: heat injected at
   the base, diffuses upward, cools, perturbed by turbulence. SEEDED PRNG
   (`random.Random(seed)`) → deterministic frames. Heat normalized to [0, 1].
   Plus: a per-cell **base-zone flag** (blue combustion zone, bottom rows of
   the flame body) and a sparse deterministic **smoke particle** list rising
   above the flame top and fading out.
2. **Palette (pure)** — `(heat, is_base) -> (r, g, b) | None`. Multi-stop
   gradient hot→cool: white-hot (255,255,240) → yellow (255,220,80) → orange
   (255,140,0) → red-orange (220,60,20) → red (160,30,10) → dark red (90,15,8)
   → None (zero heat → empty cell). Base-zone cells render a BLUE gradient
   by heat. Smoke renders faint gray (~60,60,65). Small SEEDED per-cell
   jitter breaks color banding. 24-bit truecolor ANSI (`\x1b[38;2;R;G;B m`).
3. **Renderer (pure)** — grid + particles → one ANSI frame string, half-block
   (`▀`) characters, frame dimensions match the grid, zero heat → plain
   space.
4. **Loop (IO only)** — starts ONLY under `if __name__ == "__main__":`:
   hide cursor, ~30 FPS, clear screen per frame, flame centered in
   `shutil.get_terminal_size()` (fallback 80x24). SIGINT: stop loop, restore
   cursor (`\x1b[?25h`), reset ANSI (`\x1b[0m`), exit 0.

## Realism features (all required)

- Blue combustion base (the multicolor signature of a real flame).
- Glow: white-hot core brighter than edges (gradient).
- Flicker: global intensity noise per frame.
- Turbulence: per-cell perturbation — swaying, licking, multiple tongues,
  wide base tapering upward, not a static cone.
- Smoke: faint gray particles rising above the flame.
- No color banding: seeded per-cell jitter.

## Test contract (`tests/fire_color_test.py`, pytest `def test_*`)

- Determinism: same seed → identical rendered frame string.
- Heat field: all values in [0, 1]; the field changes between two ticks.
- Palette: every RGB component in 0–255; hot core brighter than cool edge;
  zero heat → None/empty cell.
- **Multicolor**: a rendered frame of a hot scene contains at least 4
  distinct color families (blue base, yellow, orange, red) — decode the
  emitted truecolor RGBs and assert.
- **Blue base**: base-zone cells render blue-dominant (b > r).
- Renderer: frame contains ANSI escapes; frame dimensions match the grid.
- Smoke: with a fixed seed, smoke particles appear above the flame top in
  some frame.
- `bash scripts/run.sh smoke src/fire_color.py` loads the module WITHOUT
  starting the animation (main guard).

## Acceptance (supervisor)

- rc=0, verifier=PASS, `contract_lock_violations == []`, honest run (no
  pre-existing code).
- Operator manual check: `python3 src/fire_color.py` in a real terminal —
  multicolor burning flame, Ctrl-C clean stop.
