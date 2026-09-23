# TASK-STANOK-CC-109 — Console fire: realism contract (define "maximally realistic" + achieve it)

impl: src/fire.py
test: tests/fire_realism_test.py
docs: docs/fire.md

## Goal

Implement a **maximally realistic** deterministic multicolor terminal fire in
`src/fire.py`, and prove it with a new realism test contract. The basic fire
contract is already defined by the EXISTING test file `tests/fire_basic_test.py`
(it is present in `tests/` — READ it first; it must keep passing and must NOT be
modified). Your `src/fire.py` must satisfy that basic contract AND the realism
features below.

## Stack (fixed — do not deviate)

- Python 3.11 **stdlib only**, ZERO external dependencies. `node` is NOT
  available; `python3.11` IS preinstalled.
- Single module `src/fire.py`. Do NOT create a `src/fire/` package (the
  `run.sh smoke src/*.py` contract requires a file directly under `src/`).
- Add ONE new test file: `tests/fire_realism_test.py` (pytest `def test_*`;
  `import fire` works via `pythonpath=src`).
- `scripts/run.sh` ALREADY EXISTS and dispatches by extension — use it as-is,
  do NOT rewrite it.
- `tests/fire_basic_test.py` is a protected reference contract — do NOT edit or
  weaken it; it must keep passing.

## Required architecture of `src/fire.py` (four separated concerns)

1. **Simulation (pure, deterministic)** — a 2D heat-field grid of floats in
   `[0, 1]`. Per tick: inject heat at the base row(s), diffuse upward, cool
   (decay), perturb with turbulence. SEEDED PRNG (`random.Random(seed)`) →
   deterministic frames. Per-cell **base-zone flag** (bottom rows — the blue
   combustion zone) and a sparse deterministic **smoke-particle** list (x, y,
   life) rising above the flame top and fading out.
2. **Palette (pure)** — `(heat, is_base) -> (r, g, b) | None`. Multi-stop
   gradient hot→cool: white-hot (255,255,240) → yellow (255,220,80) → orange
   (255,140,0) → red-orange (220,60,20) → red (160,30,10) → dark red (90,15,8) →
   `None` (heat below a blank threshold of at most 0.10 → empty cell).
   Base-zone cells render a BLUE gradient by heat. Smoke renders faint gray
   (~60,60,65). Small SEEDED per-cell jitter breaks color banding. 24-bit
   truecolor ANSI (`\x1b[38;2;R;G;B m`).
3. **Renderer (pure)** — grid + particles → one ANSI frame string, half-block
   (`▀`) characters, frame dimensions match the grid, zero heat → plain space.
4. **Loop (IO only)** — starts ONLY under `if __name__ == "__main__":`. ~30 FPS,
   clear screen per frame, flame centered in `shutil.get_terminal_size()`
   (fallback 80x24). SIGINT: stop loop, restore cursor (`\x1b[?25h`), reset ANSI
   (`\x1b[0m`), exit 0.

### Headless-safe main guard (REQUIRED)

`python3 src/fire.py` with a real TTY → animation loop. With **no TTY**
(`stdin </dev/null`, as `run.sh smoke` does) → render ONE frame to stdout and
exit 0 (no infinite loop). CLI flags (argparse): `--seed N`, `--width W`,
`--height H`, `--fps N`, `--frames N` (render N frames then exit 0), `--frame N`
(render exactly frame N to stdout then exit 0).

## Realism features to ACHIEVE (all required)

A real flame is not monochrome and not a static cone:
- **Blue combustion base** — bottom rows of the flame body render
  blue-dominant (the multicolor signature of a real flame).
- **White-hot core / glow** — hottest cells brighter than cooler edges.
- **Flicker** — global intensity noise per frame (consecutive frames differ).
- **Turbulence** — per-cell perturbation: swaying, licking, multiple tongues,
  wide base tapering upward (NOT a static cone).
- **Smoke** — faint gray particles rising above the flame top and fading out.
- **No color banding** — seeded per-cell jitter (adjacent equal-heat cells are
  not pixel-identical).

## Test contract — `tests/fire_realism_test.py` (write it FIRST, TDD red→green)

Decode the emitted truecolor RGBs from rendered frames where needed. Assert:
- **Multicolor**: a rendered frame of a hot scene contains at least 4 distinct
  color families (blue base, yellow, orange, red).
- **Blue base**: base-zone cells render blue-dominant (`b > r`).
- **White-hot core**: the hottest cell's RGB sum is greater than a cool edge
  cell's RGB sum.
- **Flicker**: two consecutive rendered frames (same seed, tick N and N+1)
  differ.
- **Turbulence**: the flame-top x-position varies across frames (not a static
  vertical cone).
- **Smoke**: with a fixed seed, smoke particles appear above the flame top in
  some frame.
- **No banding**: two adjacent cells with the same heat value render slightly
  different RGB (jitter).
- **Heat rises & decays**: heat injected at the base appears at a higher row
  after several ticks; a cell's heat decays over time when no new heat is
  injected.

## Acceptance

- `bash scripts/run.sh test tests/fire_realism_test.py` → exit 0.
- `bash scripts/run.sh test tests/fire_basic_test.py` → STILL exit 0 (not
  regressed).
- `bash scripts/run.sh smoke src/fire.py` → exit 0.
- No new files beyond `tests/fire_realism_test.py` (and `src/fire.py`,
  `docs/fire.md`). No external dependencies. No `conftest.py`/`pytest.ini`/
  `pyproject.toml` under `tests/`.
