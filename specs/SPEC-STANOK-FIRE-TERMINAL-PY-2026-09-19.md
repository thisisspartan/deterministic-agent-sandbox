# SPEC — Realistic multicolored terminal fire (Python), 2026-09-19

Ticket: `tickets/TASK-STANOK-CC-080.md`. Stack: **Python 3.11 stdlib**
(preinstalled, zero external dependencies). The machine zone was cleaned to
infra-only before this ticket — `src/`, `tests/`, `docs/` are empty (only
`.gitkeep`). This is a clean-room build; there is no pre-existing fire code.

## Goal

A maximally realistic, beautiful MULTICOLORED burning flame rendered in the
terminal: `python3 src/fire.py` → animated fire; Ctrl-C → clean stop (cursor
restored, ANSI state reset, exit 0).

A real flame is not monochrome orange. It has a **blue combustion base**, a
**white-hot core**, a **yellow/orange body**, **red tips**, and **faint gray
smoke** above. The rendered flame must show all of these color families
natively via 24-bit truecolor ANSI — no terminal extensions.

## Language choice (supervisor decision)

**Python 3.11, stdlib only, zero external dependencies.**
- `python3` (3.11) is preinstalled in the machine container; no toolchain
  install, no pip, no network.
- `scripts/run.sh` already dispatches the `py` stack (Phase 4.2 registry:
  `test` → `python3`, `smoke` → `python3`, `list` glob `*_test.py`). **No
  run.sh change is required or authorized by this ticket.**
- Tests use stdlib `unittest`.

## Architecture (required — keeps the animation testable headless)

`src/fire.py` is a single module with four separated concerns:

1. **Simulation (pure)** — a 2D heat-field grid. Each tick: heat is injected
   at the base, diffuses upward, cools, and is perturbed by turbulence
   (value-noise or random walk). SEEDED PRNG (`random.Random(seed)`) →
   deterministic frames for tests. Heat normalized to [0, 1]. Also maintain:
   - a **base-zone flag** per cell — the combustion zone (bottom rows of the
     flame body where fresh fuel meets air; this is what is blue in a real
     flame);
   - **smoke particles** — a sparse deterministic particle list that rises
     above the flame top and fades out.
2. **Palette (pure)** — `(heat, is_base) -> (r, g, b) | None`. Multi-stop
   gradient, hot → cool: white-hot (255,255,240) → yellow (255,220,80) →
   orange (255,140,0) → red-orange (220,60,20) → red (160,30,10) → dark red
   (90,15,8) → None (zero heat → empty cell). Base-zone cells render a BLUE
   gradient by heat (e.g. 120,180,255 → 80,120,255). Smoke renders faint gray
   (~60,60,65). Small SEEDED per-cell jitter to break color banding. Emit
   24-bit truecolor ANSI (`\x1b[38;2;R;G;B m`).
3. **Renderer (pure)** — grid + particles → one ANSI frame string. Half-block
   (`▀`) for vertical resolution. Frame dimensions match the grid. Zero heat
   → plain space, no escape.
4. **Loop (IO only)** — starts ONLY under `if __name__ == "__main__":`. Hide
   cursor, ~30 FPS, clear screen per frame, flame centered in
   `shutil.get_terminal_size()` (fallback 80x24). SIGINT: stop loop, restore
   cursor (`\x1b[?25h`), reset ANSI (`\x1b[0m`), exit 0.

## Realism features (all required)

- Blue combustion base (the multicolor signature of a real flame).
- Glow: white-hot core brighter than edges (the gradient provides this).
- Flicker: global intensity noise per frame.
- Turbulence: per-cell perturbation — flame sways and licks, multiple
  tongues, wide base tapering upward, not a static cone.
- Smoke: faint gray particles rising above the flame.
- No color banding: seeded per-cell jitter.

## Test contract (`tests/fire_test.py` — stdlib `unittest`)

- Determinism: same seed → identical rendered frame string.
- Heat field: all values in [0, 1]; the field changes between two ticks.
- Palette: every RGB component 0–255; a hot core maps brighter than a cool
  edge; zero heat → None/empty cell.
- **Multicolor**: a rendered frame of a hot scene contains at least 4
  distinct color families (blue base, yellow, orange, red) — decode the
  emitted truecolor RGBs and assert.
- **Blue base**: base-zone cells render blue-dominant (b > r).
- Renderer: the frame string contains ANSI escape sequences; frame
  dimensions match the grid.
- Smoke: with a fixed seed, smoke particles appear above the flame top in
  some frame.
- `bash scripts/run.sh smoke src/fire.py` loads the module WITHOUT starting
  the animation (the main guard).

## Docs (`docs/fire.md`)

A few lines: how to run (`python3 src/fire.py`), how to stop (Ctrl-C), how it
works (heat field + base zone + smoke → palette → renderer), FPS, and the
color model (blue base / white-hot core / yellow-orange-red body / smoke).

## Acceptance (supervisor)

- `bash scripts/run.sh test tests/fire_test.py` → all tests pass.
- `bash scripts/run.sh smoke src/fire.py` → clean load, no animation.
- rc=0, verifier=PASS, honest run (code was cleaned — no pre-existing).
- Operator manual check: `python3 src/fire.py` in a real terminal —
  realistic multicolored flame, Ctrl-C clean stop (cursor restored, exit 0).
