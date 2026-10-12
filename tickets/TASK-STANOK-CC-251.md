# TASK-STANOK-CC-251 (FIRE2-04): Interactivity & Wind Physics — non-blocking raw-mode input

impl: src/fire_input.py
edit: src/fire_main.py
test: tests/fire_input_test.py

run.sh: exists

## Context

Fourth ticket of the DOOMFIRE2 wave. `src/fire_engine.py`, `src/fire_render.py`,
`src/fire_main.py` exist. This ticket adds keyboard control in non-blocking raw
mode and wires it into the main loop. Do NOT touch any file under `tests/`
from previous tickets.

## Requirement

1. `src/fire_input.py`:
   - `parse_key(data: bytes) -> action | None` — pure parser for: `b"\x1b[D"`
     → `"wind_left"`, `b"\x1b[C"` → `"wind_right"`, `b"\x1b[A"` →
     `"intensity_up"`, `b"\x1b[B"` → `"intensity_down"`, `b"q"` / `b"\x03"` →
     `"quit"`, anything else → None.
   - `class KeyReader(fd)`: raw-mode setup via `termios`/`tty` (with restore
     on close), NON-BLOCKING poll: `read() -> action | None` must never block
     (use `select.select` with timeout 0 or O_NONBLOCK; handle EAGAIN).

2. Wire into `src/fire_main.py` (edit it):
   - FireApp gains optional `keys` (a KeyReader-like with `.read()`);
   - once per tick, before `step`: poll `keys.read()`; apply: wind_left →
     wind -= 1, wind_right → wind += 1 (clamped [-3, 3] — the engine clamps
     too), intensity_up/down → adjust the decay intensity passed to
     `field.step` (if the engine step has no intensity parameter, implement
     intensity as an extra decay applied to the value before step:
     `value -= 0 or 1` per intensity level, clamped ≥ 0 — document the choice
     in the code);
   - `"quit"` → request stop (same path as SIGINT, teardown exactly once);
   - when `keys` is None (default, and all existing tests), behavior is
     unchanged.

3. `main()`: enable KeyReader on real stdin only when stdin is a tty
   (`sys.stdin.isatty()`), so non-tty runs (CI, PTY harness) keep working.

## Tests (`tests/fire_input_test.py`, pytest)

Pure parser: each sequence → exact action; unknown bytes → None; multi-byte
noise → None. KeyReader non-blocking: with a pipe fd (os.pipe) and no data,
`read()` returns None immediately (assert it does not block — no sleep
trick); write `b"\x1b[C"` → `"wind_right"`. Wiring: with a fake keys object
driving a bounded FireApp run (fake clock/sink from the existing pattern),
wind_right increases wind used in step (observe via the injected field or a
spy), quit stops the loop with exactly one EXIT. Do not modify
`tests/fire_main_test.py` or other existing tests.
