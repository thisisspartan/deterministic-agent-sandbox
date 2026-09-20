# SPEC — Realistic multicolored terminal fire V2 (Python), 2026-09-19

Ticket: `tickets/TASK-STANOK-CC-081.md`. Stack: **Python 3.11 stdlib**
(preinstalled, zero external dependencies). This is a **rewrite of the
simulation** in the existing `src/fire.py` (CC-080). The 4-layer architecture,
test contract, and `scripts/run.sh` (py stack) are unchanged.

## Why CC-080 looked bad (root cause)

CC-080 used a **linear heat-diffusion + fast-cooling** model:
`v = v*0.68 + 0.17*down + 0.075*(l+r)` then `v *= 0.90` per tick. Heat dies
within 2–3 rows of the base, so a rendered steady-state frame is ~77% empty
and the lit cells are almost all near-black dark red; the white-hot / yellow /
orange stops of the palette are never reached except in a tiny core. Combined
with top-only half-block rendering (`▀`, bottom half always background) and a
small 40×24 grid, the result is a dark, ragged, mostly-monochrome blob with a
thin blue strip — not a fire.

## Goal

A tall, bright, genuinely **multicolored** flame: white-hot core at the fuel,
yellow/orange body, red tips, a blue combustion base, licking tongues, faint
smoke above. The full palette gradient must be visible across the flame
column, not just at the base.

## The fix: max-propagation fire algorithm

Replace the diffusion model with the classic **tropical (max-plus) fire
propagation**:

- Grid `h × w`, `y = 0` is the TOP, fuel injected in the bottom rows
  (`y >= h - BASE_ROWS`).
- Each tick, for every cell `(x, y)`:
  `new[x][y] = max(old[x-1][y+1], old[x][y+1], old[x+1][y+1]) - decay`
  i.e. a cell takes the **max of the three cells one row below it** (the row
  closer to the fuel) minus a small SEEDED random decay. Out-of-range
  neighbors count as 0.
- `decay` is a small per-cell random value (e.g. `rng.uniform(0, 0.06)`) so the
  rising front is jagged and licks (multiple tongues), not a flat cone.
- **Base injection:** the bottom rows are driven hot across a fuel band with
  per-column variation (e.g. `rng.uniform(0.85, 1.0)` per column) so the base
  is white-hot and the tongues are uneven. The fuel band may sway slowly
  (random walk) for a living flame.
- Clamp all heat to `[0, 1]`. SEEDED PRNG (`random.Random(seed)`) →
  deterministic frames for tests.
- Because heat now decays only slowly going up, the whole flame column stays
  hot → the palette's white-hot → yellow → orange → red stops all appear.

## Palette (keep, now actually exercised)

`(heat, is_base) -> (r, g, b) | None`, multi-stop hot → cool:
white-hot (255,255,240) → yellow (255,220,80) → orange (255,140,0) →
red-orange (220,60,20) → red (160,30,10) → dark red (90,15,8) → None (zero heat).
Base-zone (combustion) cells render a BLUE-dominant gradient by heat
(e.g. 120,180,255 → 80,120,255, `b > r`). Smoke renders faint gray (~60,60,65).
Small SEEDED per-cell jitter to break banding. 24-bit truecolor ANSI
(`\x1b[38;2;R;G;B m`).

## Renderer (fix the sparse look)

- **Solid flame:** each lit cell must fill its WHOLE cell — do NOT leave the
  bottom half as permanent background. Either render a full colored character
  per cell, or render two half-block rows per logical row (`▀` over `▔`) for
  extra vertical resolution. The flame body must read as a solid bright mass,
  not a dotted/striped one.
- Frame dimensions match the grid. Zero heat → plain space, no escape.

## Grid size

Larger than CC-080: width ~60–80, height ~30–40 (tune for a big flame),
centered in the terminal.

## Keep unchanged

- 4-layer architecture: simulation (pure) / palette (pure) / renderer (pure) /
  loop (IO only, `if __name__ == "__main__":`).
- `sys.stdout.isatty()` guard → headless/pipe loads without animating.
- SIGINT: restore cursor (`\x1b[?25h`), reset ANSI (`\x1b[0m`), exit 0.
- ~30 FPS, clear/home per frame, centered in `shutil.get_terminal_size()`.
- `scripts/run.sh` — DO NOT modify (py stack already present, contract lock).

## Test contract (`tests/fire_test.py` — stdlib `unittest`)

Keep the existing contract and make it genuinely pass on a bright frame:
- Determinism: same seed → identical rendered frame string.
- Heat field: all values in [0, 1]; the field changes between two ticks.
- Palette: every RGB component 0–255; hot core brighter than cool edge;
  zero heat → None/empty.
- **Multicolor:** a rendered frame of a hot scene contains at least 4 distinct
  color families (blue base, yellow, orange, red) — decode emitted truecolor
  RGBs and assert. (This must now reflect a genuinely bright frame.)
- **Blue base:** base-zone cells render blue-dominant (`b > r`).
- Renderer: frame contains ANSI escapes; frame dimensions match the grid.
- Smoke: with a fixed seed, smoke particles appear above the flame top in some
  frame.
- `bash scripts/run.sh smoke src/fire.py` loads WITHOUT starting the animation.

## Acceptance (supervisor)

- `bash scripts/run.sh test tests/fire_test.py` → all tests pass.
- `bash scripts/run.sh smoke src/fire.py` → clean load, no animation.
- rc=0, verifier=PASS, honest run.
- Operator manual check: `python3 src/fire.py` in a real terminal — tall,
  bright, multicolored flame (white-hot core / yellow-orange body / red tips /
  blue base / smoke), Ctrl-C clean stop.
