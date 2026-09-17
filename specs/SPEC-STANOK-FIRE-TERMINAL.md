# SPEC-STANOK-FIRE-TERMINAL — terminal fire (Node.js, machine-native)

Operator request (2026-09-17): an infinite terminal fire animation the operator can
launch and stop with Ctrl-C. Stack: Node.js (machine-native; Python/uv rejected —
the machine harness is Node-only and the operator chose Node).

## Requirements
1. **Doom-fire heat model** (pure, deterministic):
   - grid `cols × rows`, integer heat `0..255` (`MAX_HEAT = 255`).
   - `step()`: bottom row refilled from a seeded PRNG (mulberry32); every other
     cell = `max(0, floor((left + right + below + prev) / 4) - LOSS)` with `LOSS = 1`.
   - same seed → identical frame sequence (testable without a terminal).
2. **ANSI-256 renderer**: heat → 256-color ramp (black → red → orange → yellow →
   white), one line per row, exactly `cols` cells per line.
3. **Interactive app** (`node src/fire.js`):
   - alternate screen + hidden cursor; ~25 FPS loop.
   - **Ctrl-C (SIGINT)**: show cursor, leave alternate screen, `exit 0` (clean stop).
   - size: `COLUMNS`/`LINES` env or default 80×24; seed: `FIRE_SEED` env or 42.
4. **Headless mode** (stdout not a TTY — e.g. `run.sh smoke` with stdin=/dev/null):
   render exactly 10 frames (ANSI colors ok, no screen escapes), then `exit 0`.
   This is what makes the 10s-timeout smoke run pass.
5. **Tests** (node:test + node:assert/strict, no real-time waits):
   determinism (same seed = same frames), different seeds diverge, heat clamped
   to 0..255, decay toward cold, renderer shape (rows lines × cols cells).
6. Docs: `docs/fire.md` — how to run, Ctrl-C, env vars.

## Acceptance criteria (one machine run)
- `bash scripts/run.sh test tests/fire.test.js` → GREEN.
- `bash scripts/run.sh smoke src/fire.js` → headless 10 frames, rc=0.
- rc=0, verifier=PASS, no contract_lock violations.
- Operator manual check: `node src/fire.js` in a real terminal → fire animates,
  Ctrl-C stops it cleanly (cursor back, no leftover alt-screen state).

## Ticket
`tickets/TASK-STANOK-CC-076.md` (module: fire).
