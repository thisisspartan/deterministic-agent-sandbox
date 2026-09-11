# TASK-STANOK-CC-074 — Fire app (TTY infinite loop + headless, Ctrl+C exit)

## Contract

Create `src/main.js`:

- Entry: `node src/main.js`. The main loop runs ONLY when
  `require.main === module` (so the file can be `require`d by tests without
  side effects).
- Reads env: `FIRE_SEED` (default `1337`), `FIRE_FPS` (default `25`),
  `FIRE_FRAMES` (default `50`), `STANOK_HEADLESS` (`'1'` → force headless).
- Headless when `STANOK_HEADLESS === '1'` OR `!process.stdout.isTTY`.
- Register the `SIGINT`/`SIGTERM` handlers BEFORE starting the loop.
- **TTY mode:**
  - Write `enterTerminal()` to stdout.
  - Loop forever: `state = step(state)`; `frame = renderFrame(state,
    {mode:'ansi256'})`; write `'\x1b[H' + frame` to stdout; sleep
    `1000 / FIRE_FPS` ms.
  - On `SIGINT` or `SIGTERM`: write `leaveTerminal()` to stdout, then
    `process.exit(0)`.
- **Headless mode:**
  - Loop `FIRE_FRAMES` times: `state = step(state)`; `frame =
    renderFrame(state, {mode:'symbols'})`; write `frame + '\n\n'` to stdout;
    sleep `1000 / FIRE_FPS` ms.
  - After the loop: `process.exit(0)`.
  - On `SIGINT` or `SIGTERM`: `process.exit(0)`.
- Exports:
  - `enterTerminal()` → `'\x1b[?1049h\x1b[?25l'`
  - `leaveTerminal()` → `'\x1b[?25h\x1b[?1049l'`
- Uses `src/fire_model.js` (`createModel`, `step`) and `src/fire_render.js`
  (`renderFrame`). Built-in Node.js modules only (`node:child_process` is NOT
  needed in `main.js` — only in the tests).

## Tests (write FIRST — `tests/fire_app.test.js`, expect RED)

Use `node:test` + `node:assert/strict` + `node:child_process` (spawn
`node src/main.js`). Cover:
1. **Terminal sequences:** `require('../src/main')` →
   `enterTerminal() === '\x1b[?1049h\x1b[?25l'` and
   `leaveTerminal() === '\x1b[?25h\x1b[?1049l'`.
2. **Headless frames:** spawn with env `{STANOK_HEADLESS:'1', FIRE_FRAMES:'5',
   FIRE_FPS:'1000', FIRE_SEED:'1337'}`; expect exit code `0`; stdout contains
   exactly 5 frames (each 24 lines, the default height) separated by a single
   blank line; stdout contains NO `'\x1b'`.
3. **Determinism:** spawn twice with the same env (`STANOK_HEADLESS:'1',
   FIRE_FRAMES:'5', FIRE_FPS:'1000', FIRE_SEED:'42'`); both exit `0`; the two
   stdouts are byte-identical.
4. **SIGINT early stop:** spawn with env `{STANOK_HEADLESS:'1',
   FIRE_FRAMES:'100000', FIRE_FPS:'25', FIRE_SEED:'1337'}`; wait ~1000 ms; send
   `SIGINT`; expect the process to exit with code `0` (well before 100000
   frames).

Note: spawned processes have a pipe (non-TTY) stdout, so they are headless even
without `STANOK_HEADLESS`; set it anyway for clarity. Keep total test time well
under the 60 s `run.sh` timeout.

## Verification

`bash scripts/run.sh test tests/fire_app.test.js` → all tests PASS.

## Deliverables

- `src/main.js`
- `tests/fire_app.test.js`
- `docs/main.md` (brief: how to run, env vars, TTY vs headless, Ctrl+C behavior)

## Final report (STRICTLY ≤ 5 lines)
1. TASK: DONE
2. Files: src/main.js, tests/fire_app.test.js, docs/main.md
3. Tests: PASS
