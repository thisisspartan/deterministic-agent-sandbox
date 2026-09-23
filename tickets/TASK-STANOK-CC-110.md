# TASK-STANOK-CC-110 — Console fire: development (robustness, performance, headless testability)

impl: src/fire.py
test: tests/fire_polish_test.py
docs: docs/fire.md

## Goal

Implement a **maximally realistic, robust, performant** deterministic
multicolor terminal fire in `src/fire.py`, and prove it with a new polish test
contract. The basic + realism contracts are already defined by the EXISTING
test files `tests/fire_basic_test.py` and `tests/fire_realism_test.py` (both
are present in `tests/` — READ them first; they must keep passing and must NOT
be modified). Your `src/fire.py` must satisfy BOTH of those contracts AND the
polish/robustness features below.

## Stack (fixed — do not deviate)

- Python 3.11 **stdlib only**, ZERO external dependencies. `node` is NOT
  available; `python3.11` IS preinstalled.
- Single module `src/fire.py`. Do NOT create a `src/fire/` package (the
  `run.sh smoke src/*.py` contract requires a file directly under `src/`).
- Add ONE new test file: `tests/fire_polish_test.py` (pytest `def test_*`;
  `import fire` works via `pythonpath=src`).
- `scripts/run.sh` ALREADY EXISTS and dispatches by extension — use it as-is,
  do NOT rewrite it.
- `tests/fire_basic_test.py` and `tests/fire_realism_test.py` are protected
  reference contracts — do NOT edit or weaken them; they must keep passing.

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

## Realism features (must hold — see `tests/fire_realism_test.py`)

Blue combustion base, white-hot core brighter than edges, flicker (consecutive
frames differ), turbulence (swaying/licking/multiple tongues, wide base
tapering upward, not a static cone), smoke above the flame, no color banding
(seeded per-cell jitter).

## Development / polish features to ACHIEVE (all required)

- **Performance**: rendering must be fast enough for ~30 FPS. Rendering 300
  frames at 80x24 must complete well within a few seconds (no per-frame
  allocation storms, no O(n^3) grid ops).
- **Deterministic headless CLI**: `--frame N` renders exactly frame N to stdout
  and exits 0; `--frames N` renders N frames and exits 0. Both must be
  byte-for-byte deterministic for a fixed seed (no wall-clock or unseeded
  randomness in the frame content).
- **Robust CLI / edge cases**: `--width`/`--height` are respected; a small
  terminal (e.g. 20x10) renders without error; rendering to a pipe (no TTY)
  does not crash; invalid/missing args handled cleanly (argparse).
- **Clean shutdown**: SIGINT stops the loop, restores the cursor
  (`\x1b[?25h`), resets ANSI (`\x1b[0m`), exits 0.

## Test contract — `tests/fire_polish_test.py` (write it FIRST, TDD red→green)

- **Performance**: render 300 frames at 80x24 within a time budget (e.g.
  < 5 s) — assert elapsed time is under the budget.
- **`--frame N` determinism**: rendering frame N twice (same seed) yields
  identical output; frame N differs from frame 0 (the animation progresses).
- **`--frames N`**: renders N frames and exits 0.
- **Small terminal**: a 20x10 render completes without error and has the
  expected dimensions.
- **Flag respect**: `--width`/`--height` change the rendered frame dimensions.
- **Non-tty safety**: the pure render path works when stdout is not a TTY
  (no crash, valid frame string).
- **Integration determinism**: a 60-frame fixed-seed run is deterministic —
  frame 0 of one run equals frame 0 of a second run.

## Acceptance

- `bash scripts/run.sh test tests/fire_polish_test.py` → exit 0.
- `bash scripts/run.sh test tests/fire_basic_test.py` → STILL exit 0.
- `bash scripts/run.sh test tests/fire_realism_test.py` → STILL exit 0.
- `bash scripts/run.sh smoke src/fire.py` → exit 0.
- No new files beyond `tests/fire_polish_test.py` (and `src/fire.py`,
  `docs/fire.md`). No external dependencies. No `conftest.py`/`pytest.ini`/
  `pyproject.toml` under `tests/`.
