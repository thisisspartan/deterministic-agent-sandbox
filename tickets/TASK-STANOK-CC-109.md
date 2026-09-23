# TASK-STANOK-CC-109 — Console fire: realism contract (define "maximally realistic" + achieve it)

impl: src/fire.py (existing — extend in place, do NOT rewrite from scratch)
test: tests/fire_realism_test.py (NEW)
docs: docs/fire.md (existing — update)

## Context

`src/fire.py` already exists (from CC-108): a working deterministic fire with
Simulation / Palette / Renderer / Loop concerns, a headless-safe main guard,
and CLI flags (`--seed`, `--width`, `--height`, `--fps`, `--frames`,
`--frame`). `tests/fire_basic_test.py` already exists and MUST keep passing.
Your job: make the fire **maximally realistic** by (a) writing the realism
test contract and (b) extending the implementation to satisfy it.

## Stack (fixed — do not deviate)

- Python 3.11 **stdlib only**, ZERO external dependencies.
- Extend the EXISTING single module `src/fire.py` (do not rewrite it from
  scratch; do not create a `src/fire/` package).
- Add ONE new test file: `tests/fire_realism_test.py` (pytest `def test_*`;
  `import fire` works via `pythonpath=src`).
- `scripts/run.sh` ALREADY EXISTS — use it as-is, do NOT rewrite it.
- `tests/fire_basic_test.py` is a protected reference contract — do NOT edit
  or weaken it; it must keep passing.

## Realism features to ACHIEVE in `src/fire.py`

A real flame is not monochrome and not a static cone. Implement ALL of:
- **Blue combustion base** — the bottom rows of the flame body render a
  blue-dominant gradient (the multicolor signature of a real flame).
- **White-hot core / glow** — the hottest cells (core) are brighter than the
  cooler edges (a gradient, not flat color).
- **Flicker** — global intensity noise per frame, so consecutive frames
  differ.
- **Turbulence** — per-cell perturbation producing swaying, licking, multiple
  tongues, and a wide base tapering upward (NOT a static cone).
- **Smoke** — faint gray particles rising above the flame top and fading out.
- **No color banding** — small seeded per-cell jitter so adjacent equal-heat
  cells are not pixel-identical.

## Test contract — `tests/fire_realism_test.py` (write it FIRST, TDD red→green)

Decode the emitted truecolor RGBs from rendered frames where needed. Assert:
- **Multicolor**: a rendered frame of a hot scene contains at least 4 distinct
  color families (blue base, yellow, orange, red).
- **Blue base**: base-zone cells render blue-dominant (`b > r`).
- **White-hot core**: the core (hottest) cell's RGB sum is greater than a cool
  edge cell's RGB sum.
- **Flicker**: two consecutive rendered frames (same seed, tick N and N+1)
  differ.
- **Turbulence**: the flame-top x-position varies across frames (the flame is
  not a static vertical cone).
- **Smoke**: with a fixed seed, smoke particles appear above the flame top in
  some frame.
- **No banding**: two adjacent cells with the same heat value render slightly
  different RGB (jitter).
- **Heat rises & decays**: heat injected at the base appears at a higher row
  after several ticks; and a cell's heat decays over time when no new heat is
  injected.

## Acceptance

- `bash scripts/run.sh test tests/fire_realism_test.py` → exit 0.
- `bash scripts/run.sh test tests/fire_basic_test.py` → STILL exit 0 (not
  regressed).
- `bash scripts/run.sh smoke src/fire.py` → exit 0.
- No new files beyond `tests/fire_realism_test.py` (and edits to
  `src/fire.py`, `docs/fire.md`). No external dependencies. No
  `conftest.py`/`pytest.ini`/`pyproject.toml` under `tests/`.
