# SPEC — Maximally realistic console fire (Python 3.11 stdlib), 2026-09-23

Three sequential machine tickets, each ending GREEN (rc=0, verifier=PASS,
`contract_lock_violations == []`). The split is architecture → realism →
development so no single ticket is a garbage fireball: each phase is
verifiable and builds on the previous.

- **CC-108** — Architecture: working skeleton + basic contract.
- **CC-109** — Realism: the "maximally realistic" test contract + features.
- **CC-110** — Development: robustness, performance, headless testability.

## Stack (fixed)

Python 3.11 stdlib ONLY, ZERO external dependencies (node is NOT in the
machine image; python3.11 IS preinstalled). Single module `src/fire.py`
(a package `src/fire/` would break the `run.sh smoke src/*.py` glob — the
smoke contract requires a file directly under `src/`). Tests:
`tests/*_test.py` (pytest, `pythonpath=src`). Entry: `scripts/run.sh`
(unchanged — it already dispatches by extension).

## Module contract — `src/fire.py` (four separated concerns)

1. **Simulation (pure, deterministic)** — 2D heat-field grid `[0,1]`.
   Per tick: heat injected at the base, diffuses upward, cools, perturbed
   by turbulence. SEEDED PRNG (`random.Random(seed)`) → deterministic frames.
   Per-cell **base-zone flag** (blue combustion zone, bottom rows) and a
   sparse deterministic **smoke-particle** list rising above the flame top
   and fading out.
2. **Palette (pure)** — `(heat, is_base) -> (r,g,b) | None`. Multi-stop
   gradient hot→cool: white-hot (255,255,240) → yellow (255,220,80) → orange
   (255,140,0) → red-orange (220,60,20) → red (160,30,10) → dark red (90,15,8)
   → None (zero heat → empty cell). Base-zone cells render a BLUE gradient by
   heat. Smoke renders faint gray (~60,60,65). Small SEEDED per-cell jitter
   breaks color banding. 24-bit truecolor ANSI (`\x1b[38;2;R;G;B m`).
3. **Renderer (pure)** — grid + particles → one ANSI frame string, half-block
   (`▀`) characters, frame dimensions match the grid, zero heat → plain space.
4. **Loop (IO only)** — starts ONLY under `if __name__ == "__main__":`.
   ~30 FPS, clear screen per frame, flame centered in
   `shutil.get_terminal_size()` (fallback 80x24). SIGINT: stop loop, restore
   cursor (`\x1b[?25h`), reset ANSI (`\x1b[0m`), exit 0.

### Headless-safe main guard (required — makes smoke + CLI testable)

`python3 src/fire.py` with a real TTY → interactive animation loop.
`python3 src/fire.py` with **no TTY** (smoke runs `stdin </dev/null`) → render
ONE frame to stdout and exit 0 (no infinite loop → smoke passes in <10s).
CLI flags (argparse): `--seed N`, `--width W`, `--height H`, `--fps N`,
`--frames N` (render N frames then exit 0), `--frame N` (render exactly frame
N to stdout then exit 0). `--frame`/`--frames` make the animation
deterministically testable headlessly.

## Realism features (all required by CC-109)

- Blue combustion base (the multicolor signature of a real flame).
- Glow: white-hot core brighter than edges (gradient).
- Flicker: global intensity noise per frame (consecutive frames differ).
- Turbulence: per-cell perturbation — swaying, licking, multiple tongues,
  wide base tapering upward, NOT a static cone.
- Smoke: faint gray particles rising above the flame top.
- No color banding: seeded per-cell jitter.

## Test contract (one NEW test file per ticket — contract_lock-safe)

Each ticket adds its OWN new `tests/*_test.py` (new files are writable;
pre-existing test files from earlier tickets are protected and must keep
passing — the verifier runs ALL of them).

- **CC-108 → `tests/fire_basic_test.py`**: module imports without animation;
  determinism (same seed → identical frame string); heat field in [0,1] and
  changes between two ticks; palette RGB in 0–255 and zero heat → None;
  renderer frame contains ANSI escapes and matches grid dimensions;
  `run.sh smoke src/fire.py` loads without starting the animation.
- **CC-109 → `tests/fire_realism_test.py`**: a hot frame contains ≥4 distinct
  color families (blue base, yellow, orange, red) — decode emitted truecolor
  RGBs; base-zone cells render blue-dominant (b > r); white-hot core brighter
  than cool edge (core RGB sum > edge RGB sum); flicker (consecutive frames
  differ); turbulence (flame-top x-position varies across frames — not a
  static cone); smoke particles appear above the flame top in some frame
  (fixed seed); no banding (adjacent equal-heat cells differ slightly);
  heat rises (base heat appears higher after ticks) and decays over time.
- **CC-110 → `tests/fire_polish_test.py`**: performance (render 300 frames at
  80x24 within a time budget, e.g. <5s → 30 FPS achievable); `--frame N`
  renders exactly frame N deterministically; `--frames N` renders N frames and
  exits 0; small terminal (20x10) renders without error; width/height flags
  respected; non-tty render to a pipe does not crash; a 60-frame fixed-seed
  run is deterministic (frame 0 of run A == frame 0 of run B).

## Acceptance (supervisor, per ticket)

- rc=0, verifier=PASS, `contract_lock_violations == []`.
- Operator manual check (after CC-110): `python3 src/fire.py` in a real
  terminal — maximally realistic multicolor burning flame, Ctrl-C clean stop
  (cursor restored, ANSI reset, exit 0).
