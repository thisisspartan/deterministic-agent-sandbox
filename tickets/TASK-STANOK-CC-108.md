# TASK-STANOK-CC-108 — Console fire: architecture (working skeleton + basic contract)

impl: src/fire.py
test: tests/fire_basic_test.py
docs: docs/fire.md

## Goal

Build a WORKING, deterministic, multicolor-capable terminal fire as a single
Python module `src/fire.py`, with a clean internal architecture and a basic
test contract that proves the skeleton works end-to-end. This is the
foundation ticket — it must render a real (if simple) animated flame and pass
its basic tests. Later tickets (CC-109 realism, CC-110 development) extend it.

## Stack (fixed — do not deviate)

- Python 3.11 **stdlib only**, ZERO external dependencies. `node` is NOT
  available; `python3.11` IS preinstalled.
- Single module `src/fire.py`. Do NOT create a `src/fire/` package (the
  `run.sh smoke src/*.py` contract requires a file directly under `src/`).
- Tests: `tests/fire_basic_test.py` (pytest `def test_*`; `src` is on
  `sys.path` via `pythonpath=src`, so `import fire` works).
- `scripts/run.sh` ALREADY EXISTS and dispatches by extension — use it as-is,
  do NOT rewrite it.

## Required internal architecture of `src/fire.py` (four separated concerns)

1. **Simulation (pure, deterministic)** — a 2D heat-field grid of floats in
   `[0, 1]`. Per tick: inject heat at the base row(s), diffuse upward, cool
   (decay), perturb with turbulence. Use a SEEDED PRNG (`random.Random(seed)`)
   so frames are deterministic. Maintain a per-cell **base-zone flag** (the
   bottom rows of the flame body — the blue combustion zone) and a sparse
   deterministic **smoke-particle** list (each particle: x, y, life) that
   rises above the flame top and fades out.
2. **Palette (pure)** — a function `(heat, is_base) -> (r, g, b) | None`.
   Multi-stop gradient hot→cool: white-hot (255,255,240) → yellow (255,220,80)
   → orange (255,140,0) → red-orange (220,60,20) → red (160,30,10) → dark red
   (90,15,8) → `None` (zero heat → empty cell). Base-zone cells render a BLUE
   gradient by heat. Smoke renders faint gray (~60,60,65). Add small SEEDED
   per-cell jitter to break color banding. Emit 24-bit truecolor ANSI
   (`\x1b[38;2;R;G;B m`).
3. **Renderer (pure)** — grid + particles → one ANSI frame string using
   half-block (`▀`) characters. Frame dimensions must match the grid. Zero
   heat → plain space.
4. **Loop (IO only)** — starts ONLY under `if __name__ == "__main__":`.
   ~30 FPS, clear screen per frame, flame centered in
   `shutil.get_terminal_size()` (fallback 80x24). On SIGINT: stop the loop,
   restore the cursor (`\x1b[?25h`), reset ANSI (`\x1b[0m`), exit 0.

## Headless-safe main guard (REQUIRED)

`python3 src/fire.py` must behave as:
- With a real TTY (interactive terminal) → run the animation loop.
- With **no TTY** (e.g. `stdin </dev/null`, as `run.sh smoke` does) → render
  ONE frame to stdout and exit 0 (NO infinite loop — smoke must pass in <10s).
- CLI flags via argparse: `--seed N`, `--width W`, `--height H`, `--fps N`,
  `--frames N` (render N frames then exit 0), `--frame N` (render exactly
  frame N to stdout then exit 0). These make the animation deterministically
  testable headlessly.

## Test contract — `tests/fire_basic_test.py` (write it FIRST, TDD red→green)

- Module imports WITHOUT starting the animation (importing `fire` has no IO
  side effects).
- Determinism: same seed → identical rendered frame string.
- Heat field: all values in `[0, 1]`; the field changes between two ticks.
- Palette: every RGB component in 0–255; zero heat → `None`/empty cell.
- Renderer: frame contains ANSI escapes; frame dimensions match the grid.
- `bash scripts/run.sh smoke src/fire.py` loads the module WITHOUT starting
  the animation (exit 0).

## Acceptance

- `bash scripts/run.sh test tests/fire_basic_test.py` → exit 0.
- `bash scripts/run.sh smoke src/fire.py` → exit 0 (no animation hang).
- `python3 src/fire.py --frame 0` prints one frame and exits 0.
- Document the module contract in `docs/fire.md` (brief).
- No new files beyond `src/fire.py`, `tests/fire_basic_test.py`,
  `docs/fire.md`. No external dependencies. No `conftest.py`/`pytest.ini`/
  `pyproject.toml` under `tests/`.
