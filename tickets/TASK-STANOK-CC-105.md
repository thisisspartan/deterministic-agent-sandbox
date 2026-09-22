# TASK-STANOK-CC-105 — Realistic multicolored terminal fire (Python)

impl: src/fire_color.py
test: tests/fire_color_test.py
docs: docs/fire_color.md

Implement a maximally realistic, MULTICOLORED burning flame rendered in the
terminal. Running `python3 src/fire_color.py` must show an animated fire;
pressing Ctrl-C must stop it cleanly (cursor restored, ANSI state reset,
exit 0).

A real flame is not monochrome: it has a BLUE combustion base, a white-hot
core, a yellow/orange body, red tips, and faint gray smoke above. Your flame
must show all of these color families natively (24-bit truecolor ANSI, no
terminal extensions).

## Stack

Python 3.11 (preinstalled at `/usr/bin/python3`), **stdlib only, ZERO
external dependencies** (no pip installs). `src/`, `tests/`, `docs/` are
empty — this is a fresh project; `scripts/run.sh` already exists with a
py stack (pytest) — use it as-is, do NOT modify it.

## Architecture (required — the animation must be testable headless)

`src/fire_color.py` is a single module with four separated concerns:

1. **Simulation (pure function(s))** — a 2D heat-field grid. Each tick:
   heat is injected at the base, diffuses upward, cools, and is perturbed
   by turbulence (value-noise or random walk). Use a SEEDED PRNG
   (`random.Random(seed)`) so frames are deterministic for tests. Heat
   values normalized to [0, 1]. Also maintain:
   - a **base-zone flag** per cell: the combustion zone (the bottom rows of
     the flame body where fresh fuel meets air — this is what is blue in a
     real flame);
   - **smoke particles**: a sparse deterministic particle list that rises
     above the flame top and fades out.
2. **Palette (pure function)** — `(heat, is_base) -> (r, g, b) | None`.
   Multi-stop gradient, hot → cool: white-hot (255,255,240) → yellow
   (255,220,80) → orange (255,140,0) → red-orange (220,60,20) → red
   (160,30,10) → dark red (90,15,8) → None (zero heat → empty cell).
   Base-zone cells render a BLUE gradient by heat (e.g. 120,180,255 →
   80,120,255). Smoke particles render faint gray (~60,60,65). Apply a small
   SEEDED per-cell jitter to break color banding. Emit 24-bit truecolor
   ANSI (`\x1b[38;2;R;G;B m`).
3. **Renderer (pure function)** — grid + particles → one ANSI frame string.
   Use half-block (`▀`) characters for vertical resolution. Frame
   dimensions must match the grid. Zero heat → plain space, no escape.
4. **Loop (IO only)** — starts ONLY when run as main
   (`if __name__ == "__main__":` guard): hide the cursor, animate at
   ~30 FPS, clear the screen each frame, flame centered in
   `shutil.get_terminal_size()` (fallback 80x24). On SIGINT: stop the loop,
   restore the cursor (`\x1b[?25h`), reset ANSI (`\x1b[0m`), exit 0.

## Realism features (all required)

- Blue combustion base (the multicolor signature of a real flame).
- Glow: white-hot core brighter than edges (the gradient provides this).
- Flicker: global intensity noise per frame.
- Turbulence: per-cell perturbation so the flame sways and licks, multiple
  tongues, wide base tapering upward — not a static cone.
- Smoke: faint gray particles rising above the flame.
- No color banding: seeded per-cell jitter.

## Test contract (`tests/fire_color_test.py` — pytest `def test_*`, your
tests must assert these)

- Determinism: same seed → identical rendered frame string.
- Heat field: all values in [0, 1]; the field changes between two ticks.
- Palette: every RGB component in 0–255; a hot core maps brighter than a
  cool edge; zero heat → None/empty cell.
- **Multicolor**: a rendered frame of a hot scene contains at least 4
  distinct color families (blue base, yellow, orange, red) — decode the
  emitted truecolor RGBs and assert.
- **Blue base**: base-zone cells render blue-dominant (b > r).
- Renderer: the frame string contains ANSI escape sequences; frame
  dimensions match the grid.
- Smoke: with a fixed seed, smoke particles appear above the flame top in
  some frame.
- `bash scripts/run.sh smoke src/fire_color.py` must load the module
  WITHOUT starting the animation (the main guard above).

## Docs (`docs/fire_color.md`)

A few lines: how to run (`python3 src/fire_color.py`), how to stop (Ctrl-C),
how it works (heat field + base zone + smoke → palette → renderer), FPS,
and the color model (blue base / white-hot core / yellow-orange-red body /
smoke).

## Time discipline (required)

Work order: (1) write `tests/fire_color_test.py`, (2) implement
`src/fire_color.py`, (3) run the test suite.

- NEVER run the animation without a timeout — it runs until Ctrl-C. To
  preview headlessly use:
  `timeout 3 python3 src/fire_color.py < /dev/null | head -c 3000`
- Run the full test suite at most 2–3 times total (fix, then re-run).

## Notes

- Run your test with `bash scripts/run.sh test tests/fire_color_test.py`.
- Do not introduce any dependency beyond the Python stdlib.
- Do not modify `scripts/run.sh`.

Final report (STRICTLY <= 5 lines):
1. TASK: DONE
2. Files: <list>
3. Tests: PASS
