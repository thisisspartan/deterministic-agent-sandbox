# TASK-STANOK-CC-250 (FIRE2-03): Main Loop — FPS timing, resize-safe geometry, guaranteed teardown

impl: src/fire_main.py
test: tests/fire_main_test.py

run.sh: exists

## Context

Third ticket of the DOOMFIRE2 wave. `src/fire_engine.py` and `src/fire_render.py`
exist — import them, do not modify them. This ticket is the runnable program:
`python3 src/fire_main.py` must run the fire safely and always restore the
terminal. Design for testability: the loop logic must be drivable from tests
without a real terminal (inject the clock and the output sink).

## Requirement

`src/fire_main.py` must provide:

1. `class FireApp` with injectable dependencies: `out` (a sink object with
   `.write(str)`), `clock` (object with `.perf_counter()` and `.sleep(s)`),
   `size_fn` (returns (cols, rows), default `shutil.get_terminal_size`).
   Field height = rows * 2 (half-block).

2. `run(fps=30, max_frames=None)`:
   - writes `fire_render.ENTER` once at start;
   - loop: if a resize flag is set → recompute dimensions/buffer AT TICK
     START only (never inside step/render); `field.step(wind)`;
   - one `out.write(render_frame(...))` per frame (exactly one write per frame);
   - delta-time compensation via the injected clock; `max_frames` bounds the
     loop for tests;
   - returns cleanly.

3. Teardown, GUARANTEED and IDEMPOTENT (writes `fire_render.EXIT` exactly
   once total): via `finally` + `atexit.register` + handlers for SIGINT and
   SIGTERM that request stop. A second teardown call must be a no-op.

4. SIGWINCH handler: sets a flag only (no buffer work in the handler).

5. `main()`: parse argv (`--fps N`, default 30), build the real app
   (sys.stdout, time, shutil terminal size), run. `if __name__ == "__main__":
   main()`.

## Tests (`tests/fire_main_test.py`, pytest)

Use fake clock/sink/size (no real TTY). Cover at least: exactly one ENTER and
exactly one EXIT written for a normal bounded run; teardown idempotency
(stop via SIGINT handler path, via SIGTERM path, via exception in step — in
all three the EXIT appears exactly once); resize flag: changing size_fn between
frames → new geometry applied at the next tick start, no IndexError, old frame
count preserved; exactly one out.write per frame; delta-time: with a fake
clock the sleeps compensate the frame budget (assert the sleep call sequence
for a pinned fake).
