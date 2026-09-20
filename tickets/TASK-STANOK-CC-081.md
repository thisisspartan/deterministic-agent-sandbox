# TASK-STANOK-CC-081 — Rewrite fire simulation (max-propagation, bright multicolor)

impl: src/fire.py
test: tests/fire_test.py
docs: docs/fire.md

`src/fire.py` already exists (a terminal fire). It currently looks BAD: a dark,
ragged, mostly-monochrome blob with a thin blue strip. The cause is its
simulation model — a linear heat-diffusion + fast-cooling step
(`v = v*0.68 + 0.17*down + 0.075*(l+r)` then `v *= 0.90`) that kills heat within
2–3 rows of the base, so the palette's white-hot/yellow/orange stops are never
reached. **Rewrite the simulation** so the flame is a tall, bright, genuinely
multicolored fire. Keep the 4-layer architecture, the test contract, and the
IO loop. Do NOT change `scripts/run.sh`.

## The new simulation (required — replace the diffusion model)

Classic **max-propagation (tropical) fire**:

- Grid `h × w`, `y = 0` is the TOP; fuel is injected in the bottom rows
  (`y >= h - BASE_ROWS`).
- Each tick, for every cell `(x, y)`:
  `new[x][y] = max(old[x-1][y+1], old[x][y+1], old[x+1][y+1]) - decay`
  A cell takes the **max of the three cells one row below it** (the row closer
  to the fuel) minus a small SEEDED random `decay` (e.g. `rng.uniform(0, 0.06)`).
  Out-of-range neighbors count as 0. This makes a sharp front rise and lick
  (multiple tongues), not a flat cone.
- **Base injection:** drive the bottom rows hot across a fuel band with
  per-column variation (e.g. `rng.uniform(0.85, 1.0)` per column) so the base is
  white-hot and the tongues are uneven. The fuel band may sway slowly (random
  walk) for a living flame.
- Clamp all heat to `[0, 1]`. Use a SEEDED PRNG (`random.Random(seed)`) so
  frames are deterministic for tests.
- Because heat now decays only slowly going up, the whole flame column stays
  hot and the full palette gradient (white-hot → yellow → orange → red) shows.

## Palette (keep the multi-stop gradient — now actually exercised)

`(heat, is_base) -> (r, g, b) | None`, hot → cool: white-hot (255,255,240) →
yellow (255,220,80) → orange (255,140,0) → red-orange (220,60,20) → red
(160,30,10) → dark red (90,15,8) → None (zero heat). Base-zone (combustion)
cells render a BLUE-dominant gradient by heat (e.g. 120,180,255 → 80,120,255,
`b > r`). Smoke renders faint gray (~60,60,65). Small SEEDED per-cell jitter to
break banding. Emit 24-bit truecolor ANSI (`\x1b[38;2;R;G;B m`).

## Renderer (fix the sparse/striped look)

- **Solid flame:** each lit cell must fill its WHOLE cell — do NOT leave the
  bottom half as permanent background (the old `▀`-only rendering made it look
  dotted/striped). Either render a full colored character per cell, or render
  two half-block rows per logical row (`▀` over `▔`) for extra vertical
  resolution. The flame body must read as a solid bright mass.
- Frame dimensions match the grid. Zero heat → plain space, no escape.

## Grid size

Larger than before: width ~60–80, height ~30–40 (tune for a big flame), centered
in the terminal.

## Keep unchanged (do not break)

- 4-layer architecture: simulation (pure) / palette (pure) / renderer (pure) /
  loop (IO only, `if __name__ == "__main__":`).
- `sys.stdout.isatty()` guard → headless/pipe loads WITHOUT animating.
- SIGINT: restore cursor (`\x1b[?25h`), reset ANSI (`\x1b[0m`), exit 0.
- ~30 FPS, clear/home per frame, centered in `shutil.get_terminal_size()`
  (fallback 80x24).
- `scripts/run.sh` — DO NOT modify (py stack already present; contract lock).

## Test contract (`tests/fire_test.py` — stdlib `unittest`)

Keep the existing tests and make them genuinely pass on a bright frame:
- Determinism: same seed → identical rendered frame string.
- Heat field: all values in [0, 1]; the field changes between two ticks.
- Palette: every RGB component 0–255; a hot core maps brighter than a cool
  edge; zero heat → None/empty cell.
- **Multicolor:** a rendered frame of a hot scene contains at least 4 distinct
  color families (blue base, yellow, orange, red) — decode the emitted
  truecolor RGBs and assert. This must reflect a genuinely bright frame.
- **Blue base:** base-zone cells render blue-dominant (`b > r`).
- Renderer: the frame string contains ANSI escape sequences; frame dimensions
  match the grid.
- Smoke: with a fixed seed, smoke particles appear above the flame top in some
  frame.
- `bash scripts/run.sh smoke src/fire.py` loads the module WITHOUT starting the
  animation.

## Docs (`docs/fire.md`)

Update to match the new model: how to run (`python3 src/fire.py`), how to stop
(Ctrl-C), how it works (max-propagation heat field + base zone + smoke →
palette → renderer), FPS, and the color model (blue base / white-hot core /
yellow-orange-red body / smoke).

## Time discipline (required)

Work order: (1) update `tests/fire_test.py`, (2) rewrite `src/fire.py`,
(3) run the test suite, (4) update `docs/fire.md`.

- NEVER run the animation without a timeout — it runs until Ctrl-C. To preview
  headlessly use: `timeout 3 python3 src/fire.py < /dev/null | head -c 3000`
  (note: with the isatty guard a pipe prints nothing — that is correct).
- Run the full test suite at most 2–3 times total (fix, then re-run).
- Do not read or modify `scripts/run.sh` beyond running it.

## Notes

- Run your test with `bash scripts/run.sh test tests/fire_test.py`.
- Do not introduce any dependency beyond the Python stdlib.
- Work only in `src/`, `tests/`, `docs/`.

Final report (STRICTLY <= 5 lines):
1. TASK: DONE
2. Files: <list>
3. Tests: PASS
