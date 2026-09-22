# TASK-STANOK-CC-105 — Realistic multicolored terminal fire (Python) — RETRY 1 (shape defect)

impl: src/fire_color.py
test: tests/fire_color_test.py (existing — must keep passing, DO NOT modify it)
test: tests/fire_shape_test.py (NEW — flame-shape contract, see below)
docs: docs/fire_color.md

Implement a maximally realistic, MULTICOLORED burning flame rendered in the
terminal. Running `python3 src/fire_color.py` must show an animated fire;
pressing Ctrl-C must stop it cleanly (cursor restored, ANSI state reset,
exit 0).

A real flame is not monochrome: it has a BLUE combustion base, a white-hot
core, a yellow/orange body, red tips, and faint gray smoke above. Your flame
must show all of these color families natively (24-bit truecolor ANSI, no
terminal extensions).

## DEFECT TO FIX (previous run — read carefully)

The previous implementation passed all structural tests but rendered as a
SOLID RECTANGULAR BLOCK of `▀` cells, not a flame. Three root causes:

1. **Heat field fills the whole grid.** Per-row cooling is too weak and the
   center taper is too small, so heat reaches the top corners and the flame
   body is a filled rectangle.
2. **Palette renders near-dead heat as visible color.** Only EXACTLY 0.0
   returns None; heat in (0, ~0.15] renders as dark red `▀`, so nearly-dead
   cells fill the grid.
3. **Base injection is full-width** — the bottom row is a solid line.

Fix all three. The result must be a flame that is WIDE AT THE BASE and
NARROWS TO A POINT at the top, with a ragged licking silhouette and large
blank areas around it.

## Flame shape (REQUIRED — this is the acceptance criterion)

- **Blank threshold:** `palette()` must return `None` (blank cell, no ANSI
  escape) for heat below a blank threshold of at most 0.10.
- **Taper:** the heat field must cool strongly per row AND taper strongly
  toward the center as it rises, so the top rows of the flame body are
  mostly blank. The flame is a cone/triangle, not a block.
- **Non-solid base:** base-row injection must leave gaps (turbulence); fewer
  than 90% of base-row cells may be above the blank threshold.
- Keep: blue combustion base zone, white-hot core, flicker, turbulence
  (sway, licks, multiple tongues), smoke particles above the flame, seeded
  per-cell color jitter, determinism (same seed → identical frames).

## Stack

Python 3.11 (preinstalled at `/usr/bin/python3`), **stdlib only, ZERO
external dependencies** (no pip installs). `src/fire_color.py`,
`tests/fire_color_test.py`, `docs/fire_color.md` already exist from the
previous run — fix the implementation IN PLACE in `src/fire_color.py`.
`scripts/run.sh` already exists with the py stack (pytest) — use it as-is,
do NOT modify it.

## Architecture (required — the animation must be testable headless)

`src/fire_color.py` is a single module with four separated concerns:

1. **Simulation (pure function(s))** — a 2D heat-field grid. Each tick:
   heat is injected at the base, diffuses upward, cools, and is perturbed
   by turbulence. Use a SEEDED PRNG (`random.Random(seed)`) so frames are
   deterministic for tests. Heat values normalized to [0, 1]. Also maintain:
   - a **base-zone flag** per cell: the combustion zone (the bottom rows of
     the flame body where fresh fuel meets air — blue in a real flame);
   - **smoke particles**: a sparse deterministic particle list that rises
     above the flame top and fades out.
2. **Palette (pure function)** — `(heat, is_base, salt) -> (r, g, b) | None`.
   Multi-stop gradient, hot → cool: white-hot (255,255,240) → yellow
   (255,220,80) → orange (255,140,0) → red-orange (220,60,20) → red
   (160,30,10) → dark red (90,15,8) → None (heat below the blank threshold →
   empty cell). Base-zone cells render a BLUE gradient by heat (e.g.
   120,180,255 → 80,120,255). Smoke particles render faint gray (~60,60,65).
   Apply a small SEEDED per-cell jitter to break color banding. Emit 24-bit
   truecolor ANSI (`\x1b[38;2;R;G;B m`).
3. **Renderer (pure function)** — grid + particles → one ANSI frame string.
   Use half-block (`▀`) characters for vertical resolution. Frame
   dimensions must match the grid. Blank cells → plain space, no escape.
4. **Loop (IO only)** — starts ONLY when run as main
   (`if __name__ == "__main__":` guard): hide the cursor, animate at
   ~30 FPS, clear the screen each frame, flame centered in
   `shutil.get_terminal_size()` (fallback 80x24). On SIGINT: stop the loop,
   restore the cursor (`\x1b[?25h`), reset ANSI (`\x1b[0m`), exit 0.

## Test contract

`tests/fire_color_test.py` (EXISTING — must keep passing, DO NOT modify):
determinism, heat in [0,1], palette RGB 0–255, multicolor (≥4 color
families), blue base (b > r), ANSI escapes, smoke above flame, smoke-load
without animation.

`tests/fire_shape_test.py` (NEW — pytest `def test_*`, deterministic,
`new_state(40, 18, 42)` + 30 `step()` calls, frame = `render(st)`; the
bottom `height` rows of the frame are the flame body):

- **Taper:** mean number of non-space cells over the TOP 6 flame-body rows
  is less than HALF the mean over the BOTTOM 6 flame-body rows.
- **Blank top:** at least 50% of the cells in the top 6 flame-body rows are
  spaces.
- **Non-solid base:** fewer than 90% of the cells in heat row 0 are above
  the blank threshold.
- **Cold is blank:** `palette(0.05, False, ...)` is `None` and
  `palette(0.0, False, ...)` is `None`.

## Docs (`docs/fire_color.md`)

A few lines: how to run (`python3 src/fire_color.py`), how to stop (Ctrl-C),
how it works (heat field + base zone + smoke → palette → renderer), FPS,
and the color model (blue base / white-hot core / yellow-orange-red body /
smoke). Update it if the implementation changed.

## Time discipline (required)

Work order: (1) write `tests/fire_shape_test.py`, (2) fix
`src/fire_color.py`, (3) run the test suite.

- NEVER run the animation without a timeout — it runs until Ctrl-C. To
  preview headlessly use:
  `timeout 3 python3 src/fire_color.py < /dev/null | head -c 3000`
- Run the full test suite at most 2–3 times total (fix, then re-run).

## Notes

- Run your tests with `bash scripts/run.sh test tests/fire_color_test.py`
  and `bash scripts/run.sh test tests/fire_shape_test.py`.
- Do not introduce any dependency beyond the Python stdlib.
- Do not modify `scripts/run.sh` or `tests/fire_color_test.py`.

Final report (STRICTLY <= 5 lines):
1. TASK: DONE
2. Files: <list>
3. Tests: PASS
