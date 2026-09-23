# TASK-STANOK-CC-111 — Console fire: shape defect (flame must taper, not be a block)

impl: src/fire.py
test: tests/fire_shape_test.py
docs: docs/fire.md

## Goal

Fix a critical visual defect: the current deterministic multicolor terminal
fire renders as a **SOLID RECTANGULAR BLOCK** of `▀` cells, not a flame.
Re-implement `src/fire.py` so the flame is **WIDE AT THE BASE and NARROWS TO
A POINT at the top**, with a ragged licking silhouette and large blank areas
around it — while keeping ALL existing contracts passing.

## DEFECT TO FIX (read carefully)

The previous implementation passed all structural/realism/polish tests but
rendered as a solid block. Three root causes:

1. **Heat field fills the whole grid.** Per-row cooling is too weak and the
   center taper is too small, so heat reaches the top corners and the flame
   body is a filled rectangle.
2. **Palette renders near-dead heat as visible color.** Heat in (0, ~0.15]
   renders as dark red `▀`, so nearly-dead cells fill the grid.
3. **Base injection is full-width** — the bottom row is a solid line.

Fix all three.

## Existing contracts (must keep passing — DO NOT modify these files)

`tests/fire_basic_test.py`, `tests/fire_realism_test.py`, and
`tests/fire_polish_test.py` are present in `tests/` — READ them first. They
define the basic contract (imports, determinism, heat in [0,1], palette RGB
0–255, renderer ANSI + dims, smoke-load), the realism contract (multicolor
≥4 families, blue base b>r, white-hot core, flicker, turbulence, smoke, no
banding, heat rises & decays), and the polish contract (performance: 300
frames at 80x24 < 5 s; `--frame N`/`--frames N` determinism; small terminal
20x10; flag respect; non-tty safety; integration determinism). Your
`src/fire.py` must satisfy ALL of them AND the shape contract below.

## Stack (fixed — do not deviate)

- Python 3.11 **stdlib only**, ZERO external dependencies. `node` is NOT
  available; `python3.11` IS preinstalled.
- Single module `src/fire.py`. Do NOT create a `src/fire/` package (the
  `run.sh smoke src/*.py` contract requires a file directly under `src/`).
- Add ONE new test file: `tests/fire_shape_test.py` (pytest `def test_*`;
  `import fire` works via `pythonpath=src`).
- `scripts/run.sh` ALREADY EXISTS and dispatches by extension — use it as-is,
  do NOT rewrite it.

## Required architecture of `src/fire.py` (four separated concerns)

1. **Simulation (pure, deterministic)** — a 2D heat-field grid of floats in
   `[0, 1]`. Per tick: inject heat at the base row(s), diffuse upward, cool
   (decay), perturb with turbulence. SEEDED PRNG (`random.Random(seed)`) →
   deterministic frames. Per-cell **base-zone flag** (bottom rows — the blue
   combustion zone) and a sparse deterministic **smoke-particle** list (x, y,
   life) rising above the flame top and fading out.
2. **Palette (pure)** — `(heat, is_base) -> (r, g, b) | None` (match the
   exact signature the existing tests use). Multi-stop gradient hot→cool:
   white-hot (255,255,240) → yellow (255,220,80) → orange (255,140,0) →
   red-orange (220,60,20) → red (160,30,10) → dark red (90,15,8) → `None`
   (heat below the blank threshold → empty cell). Base-zone cells render a
   BLUE gradient by heat. Smoke renders faint gray (~60,60,65). Small SEEDED
   per-cell jitter breaks color banding. 24-bit truecolor ANSI
   (`\x1b[38;2;R;G;B m`).
3. **Renderer (pure)** — grid + particles → one ANSI frame string, half-block
   (`▀`) characters, frame dimensions match the grid, zero heat → plain space.
4. **Loop (IO only)** — starts ONLY under `if __name__ == "__main__":`. ~30
   FPS, clear screen per frame, flame centered in `shutil.get_terminal_size()`
   (fallback 80x24). SIGINT: stop loop, restore cursor (`\x1b[?25h`), reset
   ANSI (`\x1b[0m`), exit 0.

### Headless-safe main guard (REQUIRED)

`python3 src/fire.py` with a real TTY → animation loop. With **no TTY**
(`stdin </dev/null`, as `run.sh smoke` does) → render ONE frame to stdout and
exit 0 (no infinite loop). CLI flags (argparse): `--seed N`, `--width W`,
`--height H`, `--fps N`, `--frames N` (render N frames then exit 0), `--frame
N` (render exactly frame N to stdout then exit 0).

## Flame shape (REQUIRED — this is the acceptance criterion)

- **Blank threshold:** `palette()` must return `None` (blank cell, no ANSI
  escape) for heat below a blank threshold of **at most 0.10**.
- **Taper:** the heat field must cool strongly per row AND taper strongly
  toward the center as it rises, so the top rows of the flame body are
  mostly blank. The flame is a cone/triangle, not a block.
- **Non-solid base:** base-row injection must leave gaps (turbulence); fewer
  than 90% of base-row cells may be above the blank threshold.
- Keep: blue combustion base zone, white-hot core, flicker, turbulence
  (sway, licks, multiple tongues), smoke particles above the flame, seeded
  per-cell color jitter, determinism (same seed → identical frames).

## Test contract — `tests/fire_shape_test.py` (write it FIRST, TDD red→green)

Use the module's public API exactly as the existing tests use it (create a
simulation state with a fixed seed, step it a fixed number of ticks, render a
frame). The bottom `height` rows of the frame are the flame body. Assert:

- **Taper:** mean number of non-space cells over the TOP 6 flame-body rows is
  less than HALF the mean over the BOTTOM 6 flame-body rows.
- **Blank top:** at least 50% of the cells in the top 6 flame-body rows are
  spaces.
- **Non-solid base:** fewer than 90% of the cells in heat row 0 are above the
  blank threshold.
- **Cold is blank:** `palette(0.05, False, ...)` is `None` and
  `palette(0.0, False, ...)` is `None`.

## Acceptance

- `bash scripts/run.sh test tests/fire_shape_test.py` → exit 0.
- `bash scripts/run.sh test tests/fire_basic_test.py` → STILL exit 0.
- `bash scripts/run.sh test tests/fire_realism_test.py` → STILL exit 0.
- `bash scripts/run.sh test tests/fire_polish_test.py` → STILL exit 0.
- `bash scripts/run.sh smoke src/fire.py` → exit 0.
- No new files beyond `tests/fire_shape_test.py` (and `src/fire.py`,
  `docs/fire.md`). No external dependencies. No `conftest.py`/`pytest.ini`/
  `pyproject.toml` under `tests/`.

## Time discipline (required)

- NEVER run the animation without a timeout — it runs until Ctrl-C. To
  preview headlessly use: `timeout 3 python3 src/fire.py < /dev/null | head -c 3000`
- Run the full test suite at most 2–3 times total (fix, then re-run).

Final report (STRICTLY <= 5 lines):
1. TASK: DONE
2. Files: <list>
3. Tests: PASS
