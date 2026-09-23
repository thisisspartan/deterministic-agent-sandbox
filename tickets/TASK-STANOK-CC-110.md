# TASK-STANOK-CC-110 — Console fire: development (robustness, performance, headless testability)

## Context

`src/fire.py` already exists (from CC-108 + CC-109): a maximally realistic
deterministic multicolor fire with Simulation / Palette / Renderer / Loop
concerns, a headless-safe main guard, and CLI flags (`--seed`, `--width`,
`--height`, `--fps`, `--frames`, `--frame`). `tests/fire_basic_test.py` and
`tests/fire_realism_test.py` already exist and MUST keep passing. Your job:
harden the fire for real use — performance, robustness, edge cases, and
fully deterministic headless testability — and prove it with a new test file.

## Stack (fixed — do not deviate)

- Python 3.11 **stdlib only**, ZERO external dependencies.
- Extend the EXISTING single module `src/fire.py` (do not rewrite it from
  scratch; do not create a `src/fire/` package).
- Add ONE new test file: `tests/fire_polish_test.py` (pytest `def test_*`;
  `import fire` works via `pythonpath=src`).
- `scripts/run.sh` ALREADY EXISTS — use it as-is, do NOT rewrite it.
- `tests/fire_basic_test.py` and `tests/fire_realism_test.py` are protected
  reference contracts — do NOT edit or weaken them; they must keep passing.

## Development work to ACHIEVE in `src/fire.py`

- **Performance**: rendering must be fast enough for ~30 FPS. Rendering 300
  frames at 80x24 must complete well within a few seconds (no per-frame
  allocation storms, no O(n^3) grid ops).
- **Deterministic headless CLI**: `--frame N` renders exactly frame N to
  stdout and exits 0; `--frames N` renders N frames and exits 0. Both must be
  byte-for-byte deterministic for a fixed seed (no wall-clock or unseeded
  randomness in the frame content).
- **Robust CLI / edge cases**: `--width`/`--height` are respected; a small
  terminal (e.g. 20x10) renders without error; rendering to a pipe (no TTY)
  does not crash; invalid/missing args are handled cleanly (argparse).
- **Clean shutdown**: SIGINT stops the loop, restores the cursor
  (`\x1b[?25h`), resets ANSI (`\x1b[0m`), exits 0.

## Test contract — `tests/fire_polish_test.py` (write it FIRST, TDD red→green)

- **Performance**: render 300 frames at 80x24 within a time budget (e.g.
  < 5 s) — assert the elapsed time is under the budget.
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
- No new files beyond `tests/fire_polish_test.py` (and edits to
  `src/fire.py`, `docs/fire.md`). No external dependencies. No
  `conftest.py`/`pytest.ini`/`pyproject.toml` under `tests/`.
