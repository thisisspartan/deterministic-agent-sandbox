# SPEC — Realistic multicolored terminal fire (Python)

Date: 2026-09-18. Ticket: TASK-STANOK-CC-079. Label: `fire02`.

## Background

CC-078 delivered a realistic terminal fire in Node.js (`src/fire.js`). The
operator now wants the same class of deliverable in a **different language**
with an emphasis on **realistic multicolor**: a real flame is not monochrome
orange — it has a blue combustion base, a white-hot core, yellow/orange
body, red tips, and gray smoke above. The palette must show all of these
families natively, without browser/terminal extensions.

## Language choice (supervisor decision)

**Python 3.11, stdlib only, zero external dependencies.**

- `python3` (3.11.2) is preinstalled in the machine container
  (`/usr/bin/python3`); no toolchain install needed (node is NOT in the
  image — the CC-078 run installed it on the fly).
- `python3 src/fire_color.py` runs directly in a real terminal (operator
  manual check), same contract as `node src/fire.js`.
- ANSI truecolor, terminal size (`shutil.get_terminal_size`), SIGINT —
  all stdlib. Tests use stdlib `unittest` (no pytest install).

Python becomes the **second** language in the repo, explicitly authorized by
the ticket. The existing Node.js fire module stays untouched.

## Requirements

1. **Simulation (pure, deterministic).** 2D heat-field grid; seeded PRNG
   (`random.Random(seed)`). Per tick: heat injected at the base, diffuses
   upward, cools, turbulence perturbation (value-noise/random walk). Heat
   normalized to [0, 1]. A **base-zone flag** marks the combustion zone
   (bottom rows of the flame body where fresh fuel meets air — this is what
   is blue in a real flame). **Smoke particles**: a sparse deterministic
   particle list rising above the flame top, fading out.
2. **Palette (pure).** `(heat, is_base) -> (r, g, b) | None`.
   Multi-stop gradient, hot → cool:
   white-hot (255,255,240) → yellow (255,220,80) → orange (255,140,0) →
   red-orange (220,60,20) → red (160,30,10) → dark red (90,15,8) → None.
   Base-zone cells render a **blue** gradient (e.g. 120,180,255 → 80,120,255)
   by heat. Smoke particles render faint gray (~60,60,65). Per-cell
   deterministic jitter (seeded) to break color banding.
3. **Renderer (pure).** Grid + particles → one ANSI frame string.
   Half-block `▀` for vertical resolution. 24-bit truecolor
   (`\x1b[38;2;R;G;B m`). Zero heat → plain space. Frame dimensions match
   the grid.
4. **Loop (IO only).** Starts only under `if __name__ == "__main__"`.
   ~30 FPS, clear screen per frame, flame centered in
   `shutil.get_terminal_size()` (fallback 80x24), cursor hidden.
   SIGINT: stop loop, restore cursor (`\x1b[?25h`), reset ANSI (`\x1b[0m`),
   exit 0.

## Realism features (all required)

- Blue combustion base (the multicolor signature).
- White-hot core brighter than edges (glow).
- Flicker: global intensity noise per frame.
- Turbulence: per-cell perturbation — flame sways and licks, multiple
  tongues, wide base tapering upward.
- Smoke: faint gray particles above the flame.
- No color banding: seeded per-cell jitter.

## Test contract (`tests/fire_color_test.py`, stdlib `unittest`)

- Determinism: same seed → identical rendered frame string.
- Heat field: all values in [0, 1]; field changes between two ticks.
- Palette: every RGB component 0–255; hot core brighter than cool edge;
  zero heat → None/empty cell.
- **Multicolor**: a rendered frame of a hot scene contains at least 4
  distinct color families (blue base, yellow, orange, red) — assert by
  decoding the emitted truecolor RGBs.
- **Blue base**: base-zone cells render blue-dominant (b > r).
- Renderer: frame contains ANSI escapes; dimensions match the grid.
- Smoke: with a fixed seed, smoke particles appear above the flame top in
  some frame.
- `bash scripts/run.sh smoke src/fire_color.py` loads the module WITHOUT
  starting the animation (main guard).

## `scripts/run.sh` extension (explicitly authorized by the ticket)

Dispatch by extension, keep existing JS behavior byte-compatible:
- `test`: `*.test.js` → `node --test --test-force-exit` (unchanged);
  `*_test.py` → `timeout 60 python3 <file> < /dev/null`.
- `smoke`: `src/*.js` → node (unchanged); `src/*.py` →
  `timeout 10 python3 <file> < /dev/null`.
- `list`: both patterns.
Existing JS files (`src/fire.js`, `tests/fire.test.js`) are NOT modified and
NOT part of this ticket's verification (node is not in the container image;
do not install it).

## Acceptance

- `bash scripts/run.sh test tests/fire_color_test.py` → all tests pass.
- `bash scripts/run.sh smoke src/fire_color.py` → clean load, no animation.
- Operator manual check: `python3 src/fire_color.py` in a real terminal —
  multicolored realistic flame (blue base, white/yellow/orange/red body,
  smoke), Ctrl-C stops cleanly (cursor restored, exit 0).
