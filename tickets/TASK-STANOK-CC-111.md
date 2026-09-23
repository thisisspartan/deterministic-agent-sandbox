# TASK-STANOK-CC-111 — Console fire: shape defect (flame must taper, not be a block) — RETRY 2

test: tests/fire_shape_test.py
docs: docs/fire.md

## Goal

Fix a critical visual defect in the EXISTING deterministic multicolor
terminal fire: it renders as a **SOLID RECTANGULAR BLOCK** of `▀` cells, not
a flame. Fix `src/fire.py` **IN PLACE** (it already exists — do NOT rewrite
it from scratch; make targeted changes) so the flame is **WIDE AT THE BASE
and NARROWS TO A POINT at the top**, with a ragged licking silhouette and
large blank areas around it — while keeping ALL existing contracts passing.

## DEFECT TO FIX (read carefully)

The current implementation passes all structural/realism/polish tests but
renders as a solid block. Three root causes:

1. **Heat field fills the whole grid.** Per-row cooling is too weak and the
   center taper is too small, so heat reaches the top corners and the flame
   body is a filled rectangle.
2. **Palette renders near-dead heat as visible color.** Heat in (0, ~0.15]
   renders as dark red `▀`, so nearly-dead cells fill the grid.
3. **Base injection is full-width** — the bottom row is a solid line.

Fix all three with targeted changes to the simulation and palette.

## Current state (from the interrupted previous attempt — read first)

The current `src/fire.py` is a PARTIAL fix: the flame already tapers
(top frame rows are blank, base is wide) and `tests/fire_basic_test.py` +
`tests/fire_polish_test.py` pass — but `tests/fire_realism_test.py`
currently FAILS (a regression from the in-progress edits). Diagnose which
realism assertions fail and fix that regression with targeted changes; do
NOT redo the shape work that already holds.

## Existing contracts (must keep passing — DO NOT modify these files)

`tests/fire_basic_test.py`, `tests/fire_realism_test.py`, and
`tests/fire_polish_test.py` are present in `tests/` — READ them first, and
READ `src/fire.py` to learn the exact public API (state creation, step,
palette signature, render). They define the basic contract (imports,
determinism, heat in [0,1], palette RGB 0–255, renderer ANSI + dims,
smoke-load), the realism contract (multicolor ≥4 families, blue base b>r,
white-hot core, flicker, turbulence, smoke, no banding, heat rises & decays),
and the polish contract (performance: 300 frames at 80x24 < 5 s; `--frame
N`/`--frames N` determinism; small terminal 20x10; flag respect; non-tty
safety; integration determinism). Your fixed `src/fire.py` must satisfy ALL
of them AND the shape contract below.

## Stack (fixed — do not deviate)

- Python 3.11 **stdlib only**, ZERO external dependencies. `node` is NOT
  available; `python3.11` IS preinstalled.
- Single module `src/fire.py` (EXISTS — fix in place). Do NOT create a
  `src/fire/` package.
- Add ONE new test file: `tests/fire_shape_test.py` (pytest `def test_*`;
  `import fire` works via `pythonpath=src`).
- `scripts/run.sh` ALREADY EXISTS and dispatches by extension — use it as-is,
  do NOT rewrite it.

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
  `palette(0.0, False, ...)` is `None` (match the palette's exact signature).

## Docs (`docs/fire.md`)

A few lines: how to run (`python3 src/fire.py`), how to stop (Ctrl-C), how it
works (heat field + base zone + smoke → palette → renderer), FPS, the color
model (blue base / white-hot core / yellow-orange-red body / smoke), and the
flame shape (tapering cone, blank threshold).

## Acceptance

- `bash scripts/run.sh test tests/fire_shape_test.py` → exit 0.
- `bash scripts/run.sh test tests/fire_basic_test.py` → STILL exit 0.
- `bash scripts/run.sh test tests/fire_realism_test.py` → STILL exit 0.
- `bash scripts/run.sh test tests/fire_polish_test.py` → STILL exit 0.
- `bash scripts/run.sh smoke src/fire.py` → exit 0.
- No new files beyond `tests/fire_shape_test.py` (and the in-place fix to
  `src/fire.py`, `docs/fire.md`). No external dependencies. No
  `conftest.py`/`pytest.ini`/`pyproject.toml` under `tests/`.

## Time discipline (required)

- Work order: (1) write `tests/fire_shape_test.py`, (2) fix `src/fire.py`
  (targeted changes only), (3) run the test suite.
- NEVER run the animation without a timeout — it runs until Ctrl-C. To
  preview headlessly use: `timeout 3 python3 src/fire.py < /dev/null | head -c 3000`
- Run the full test suite at most 2–3 times total (fix, then re-run).

Final report (STRICTLY <= 5 lines):
1. TASK: DONE
2. Files: <list>
3. Tests: PASS
