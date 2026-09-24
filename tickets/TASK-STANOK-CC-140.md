# TASK-STANOK-CC-140 — `run --background --follow` / `wait`: one call carries the verdict

Supervisor-executed (`launcher/` is RO in the container). Filed from the
operator's SMOKE-02 incident: the run PASSED, but **no verdict came back to the
TUI**. Root cause was the supervisor protocol, not the run.

## Incident

`evidence/smoke-tools/summary.json` has `rc: 0`, `verifier: "PASS"`,
`probe_result: "CLEAN-FIRST"`, `contract_lock_violations: []`; `launch.sh status
smoke-tools` says `done`; `smoke-tools.launch.log` ends `VERIFIER: PASS` /
`RUN FINISHED: rc=0`. The supervisor transcript
(`~/.claude/projects/-home-hermes-darkcast/de65bfa9-….jsonl`) shows the exact
failure: it issued `run … smoke-tools --background` (child PID 2571176), then
wrote "Этот тикет уже запущен … жду завершения и отчитаюсь по summary.json" and
**ended its turn without issuing the §3 step‑2 wait task**.

The TUI "return" was never the machine's — it was the completion notification of
that separate background Bash task (`while launch.sh status <label> | grep -q
running`). No task → no notification → nothing in the TUI, while the verdict sat
in `summary.json` the whole time. The OPIK trace cannot carry it either: the
external verifier runs in-process *after* the session and is not traced.

## Change

- `stanok.py`: `cmd_status`'s body becomes `_status_dict(label)` (single source)
  plus a thin `cmd_status`. New `cmd_wait(label, timeout_s=2700)`: poll
  `_status_dict` every `WAIT_POLL_S` (5 s) until the state is not `running`,
  print the final status JSON, return 0 — or return 124 on the 45‑min cap.
- `launch_background`: new `args.follow`. When set, it blocks in `cmd_wait`
  after the `.running` marker is confirmed (and also on the fast-abort path,
  where a summary already exists). rc=17 launch failures still return
  immediately — `--follow` never waits on a launch that never happened.
- CLI: `run` gains `--follow` (implies `--background`); new `wait <label>
  [--timeout N]` subcommand. `--follow` is a parent-only flag — it is not in
  `_inner_run_argv`, so the detached child stays a plain sync run.
- `CLAUDE.supervisor.md`: §3 rewritten from the 3-call to the **2-call** pattern
  — ONE background `run … --background --follow` (its notification IS the
  verdict trigger) → Read `summary.json`. §6 now forbids `run --background`
  without `--follow` and the separate hand-rolled wait loop.
- `README.md` + `launch.sh`: CLI surface updated (`--follow`, `wait`).

## Verification

- `py_compile` (stanok.py), `bash -n` (launch.sh).
- New `launcher/tests_harness/test_wait_follow.py` (7 tests): `wait` prints
  done+fields / dead / timeout(rc=124) / missing; `status` and `wait` agree via
  `_status_dict`; the CLI wires the `wait` subcommand (subprocess → missing) and
  accepts `run … --follow` without `--background` (subprocess → ticket gate
  rc=13); `--follow` does not leak into the child argv.
- `bash hooks/doctor.sh` — **158 passed, 0 skipped on a clean tree** (151 + 7).

## Non-goals / residuals

- `cmd_wait` returns 0 for any terminal state (done/dead/missing) and 124 on
  timeout; the verdict itself is the printed JSON / `summary.json`, which is
  what the §3 verdict rules read. It does not re-encode the run's rc as its own.
- The detached child, the Docker supervision and the `.running` marker semantics
  are unchanged — only who waits, and in which process, moved.
- A supervisor can still *decline* to issue the single background call; what is
  now impossible is the SMOKE-02 shape — "launched and then waited nowhere".
