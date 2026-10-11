# TASK-STANOK-CC-244 (FIRE-05): Headless PTY integration — byte-level proof the fire renders and sanitizes the terminal

test: tests/fire_pty_test.py

run.sh: exists

## Context

Final ticket of the DOOMFIRE wave. `src/fire_engine.py`, `src/fire_render.py`,
`src/fire_main.py`, `src/fire_input.py` exist. This ticket adds NO src code —
only an end-to-end test that runs the real program under a real PTY using the
Python STANDARD LIBRARY `pty` module (node-pty is NOT available in this image;
do not try to install anything). The test is the machine-side proof that a
human is not needed to verify terminal behavior.

## Requirement

`tests/fire_pty_test.py` (pytest, stdlib only: `pty`, `os`, `signal`, `select`,
`time`):

1. Spawn `python3 src/fire_main.py` under a PTY (`pty.openpty()`, child gets
   the slave as stdin/stdout/stderr, `TERM=xterm-256color` in the child env,
   window size set to 80×24 via `fcntl.ioctl(slave, termios.TIOCSWINSZ, ...)`).
   Run from the repo root so `src/` imports resolve.

2. Read raw bytes from the master for ~1.5 s (select loop). Assert on the raw
   stream:
   - contains `b"\xe2\x96\x80"` (▀) — half-block rendering is happening;
   - contains `b"\x1b[38;2;"` and `b"\x1b[48;2;"` — truecolor fg+bg;
   - starts with the alt-screen enter `b"\x1b[?1049h"`.

3. Resize survival: change the PTY window size (e.g. 60×12 → TIOCSWINSZ,
   kernel delivers SIGWINCH to the child), keep reading ~0.5 s — the child must
   still produce frames (more ▀ bytes) and must NOT die.

4. Clean exit: send SIGINT to the child (`os.kill(pid, signal.SIGINT)`),
   reap it; assert the child exits with code 0 and the captured stream contains
   the teardown `b"\x1b[?25h"` and `b"\x1b[?1049l"` — the terminal is restored.

5. Robustness: the test must not hang forever — bound every read with a
   timeout; if the child is still alive at the end, kill it (SIGKILL) and fail.
   All temp files (if any) go under `$TMPDIR` only.

## Acceptance (supervisor-side)

The test runs green via `scripts/run.sh test --all` inside the pod AND in the
fresh-check container. No src/ changes are allowed in this ticket.
