# TASK-STANOK-CC-207: loop-guard circuit breaker — the run ends with `probe_result: "LOOP-TRAP"`

Executor: **supervisor** (supervisor-executed ticket — `.claude/hooks/` and
`launcher/` are outside the machine's writable zones; no machine launch, no
manifest header). TDD: RED harness tests land BEFORE the fix.

## Incident (the required citation — CC-204-retry3, REVIEW §1/§4.2)

Turn 2: 31 identical `Read` calls on `README.md`, 32 word-for-word identical
assistant blocks. The hook denied from the 10th call on (22 denials) — the
denial text entered context as just another line and did not break the loop.
Cost: 1584 s, 64 125 output tokens, `prefix_break: true`. The warning
mechanism is empirically insufficient: the software must bound the loop.

## Existing primitives (reused, not reimplemented — §7)

- Detector: `.claude/hooks/loop-guard.py` (PreToolUse command hook, registered
  in `.claude/settings.json`) — counts CONSECUTIVE identical calls
  (tool name + args hash); any different call resets. Keep the algorithm
  EXACTLY as-is.
- Transport: the hook process inherits the CLI's env; `build_agent_env()`
  (`stanok.py:1125`) is the sanctioned runtime-env channel. `LOG_DIR/<label>`
  is mounted rw in the container (`sandbox.py:108`) and is the launcher's own
  per-run dir (`_live_dir`) — the marker channel needs no new mount.

## Change 1 — the hook signals termination at N=5

`.claude/hooks/loop-guard.py`:
- `THRESHOLD = 10` → `5` (single threshold: at the 5th consecutive identical
  call the hook denies AND signals termination). The operator-confirmed value.
- Signal: write a JSON marker to the path in env `STANOK_LOOP_TRAP_FILE`
  (unset → no marker: outside a stanok session the hook stays a pure warning).
  Marker body: `{"tool": <name>, "hash": <sha256>, "n": <count>, "ts": <iso>}`.
  Create parent dirs if needed. Fail-open invariant preserved: ANY marker
  write failure never blocks or fails the turn (the deny still happens).
- Deny text at n>=5: state that the session is being terminated (not
  "don't repeat" — repetition is no longer the model's decision to make).

## Change 2 — the launcher consumes the signal

`launcher/stanok.py`:
- `build_agent_env()`: add `"STANOK_LOOP_TRAP_FILE": os.path.join(_live_dir,
  "loop-trap.json")`.
- `_execute_turn`: inside `async for msg in client.receive_response():`, after
  `_write_stream_msg`, check the marker file (`os.path.exists` — a stat per
  message, no polling loop); on presence, read it (best-effort) and break the
  stream loop. Return it as a 5th tuple element `loop_trap: dict | None`.
- `run_continuous_session`: immediately after the `wait_for` block — if
  `loop_trap`: log, `await client.interrupt()` (best-effort), set
  `job["probe_result"] = "LOOP-TRAP"`, `job["loop_trap"] = <marker>`,
  `job["verifier"] = "FAIL"`, `job["error"] = "LOOP-TRAP: <tool> repeated
  <n>x consecutively — session terminated by the circuit breaker"`,
  `return 1`. NO fix prompt, NO local retries: a retry re-enters the same
  loop (the marker is cumulative for the session).
- The check is mid-turn (per message), not only at turn end — CC-204-retry3
  burned the whole 1584 s turn before any turn-end check could fire.

## Change 3 — supervisor protocol

`CLAUDE.supervisor.md` §3 (Verdict from summary.json): add —
`probe_result: "LOOP-TRAP"` → defect class B: refine the ticket (the loop was
designed by the ticket, not by the code), do NOT relaunch the same ticket, do
not count it toward "3 consecutive failed attempts" as a code defect… (it
does count — the ticket is what gets refined).

## Tests (RED first, in `launcher/tests_harness/`)

`test_loop_guard.py` (re-pin the changed contract — these tests pin the OLD
threshold, which this ticket changes):
- `test_tenth_identical_denied` → `test_fifth_identical_denied`: 4 allowed,
  5th denied (rc=2).
- `test_counter_resets_on_different_call`, `test_non_bash_tools_counted`:
  adjust the 9-call runs to 4.
- `test_tdd_cycle_not_denied`: unchanged (must stay green — alternating calls
  never trip).
- NEW `test_marker_written_at_fifth`: with `STANOK_LOOP_TRAP_FILE` set, the
  4th call writes no marker; the 5th writes valid JSON with
  `tool`/`hash`/`n==5`.
- NEW `test_marker_fail_open`: unwritable marker path (e.g. a directory in
  its place) → the call is still denied (rc=2), the hook does not crash.
- NEW `test_no_env_no_marker`: `STANOK_LOOP_TRAP_FILE` unset → deny still
  happens, no marker written anywhere.

`test_verdict_safety.py` (or a new `test_loop_trap.py` beside it):
- NEW pure-function tests for the launcher side: a helper
  `_read_loop_trap(marker_path) -> dict | None` (unreadable/missing → None)
  tested directly; the verdict branch tested on a synthetic `job` dict exactly
  like `test_contract_lock_forced_fail_*` (probe_result/verifier/error set).

No synthetic full-session stub — the e2e proof is the next real machine run;
inventing a session stub harness would be a new mechanism without an incident.

## Non-goals

Detector algorithm unchanged; `sandbox.py` untouched; no temperature/prompt
changes (REVIEW §3.3/§3.4); no new rc (1 is the existing defect code);
`STANOK_MAX_AGENT_TURNS` untouched.

## Acceptance

1. RED first: the re-pinned + new hook tests fail against the current hook
   (real assertion failures).
2. After the fix: `pytest launcher/tests_harness` fully green.
3. A real launch that loops ends in < 1 turn with `probe_result:
   "LOOP-TRAP"` in summary.json (verified on the first run that trips it;
   if no run trips it, the unit evidence + the CC-204-retry3 replay reasoning
   stand — do NOT fabricate a looping ticket just to prove the breaker).
4. `CLAUDE.supervisor.md` §3 carries the LOOP-TRAP protocol.
5. Submodule commit + parent gitlink bump; STATUS.md/CONTEXT.md entries.
