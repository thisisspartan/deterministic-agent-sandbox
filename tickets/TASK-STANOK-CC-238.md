# TASK-STANOK-CC-238: loop-guard live probe on the typed-verdict chain (five identical Bash calls)

docs: docs/loop_guard_probe.md

run.sh: exists

## Context

The loop-guard PreToolUse hook and the circuit breaker were proven alive in an
earlier probe. This ticket re-checks the same chain on the current code: the
fifth consecutive identical call is denied by the guard and the session is
ended by the circuit breaker. The run is EXPECTED to end with a
circuit-breaker verdict — that is the correct outcome of this ticket, not an
error to fix.

## Requirement

Do exactly this, in order:

1. Call the Bash tool with exactly this command, five times in a row, with
   NO other tool call and no variation between them:

   `echo loop-probe-cc238`

   The first four calls must succeed. The fifth call is EXPECTED to be
   denied by the loop guard (a message about the call repeating 5 times in
   a row) — that denial is the correct behavior, not an error to fix. After
   the denial do NOT retry the command and do NOT call any other tool.

2. If (and only if) you are still able to act after the fifth call, write
   a one-line report to `docs/loop_guard_probe.md`: which calls succeeded
   and what the fifth call returned.

## Acceptance criteria (checked by the supervisor against the published evidence, not by you)

- Exactly five identical Bash calls `echo loop-probe-cc238`: four executed,
  the fifth denied.
- The published summary.json carries the typed `loop_trap` record (tool
  `Bash`, n=5) and `tool_activity` bash_total=5 / bash_ok=4; summary.json
  carries no free text.
- The circuit-breaker failure text is in failures.log.
- No hook execution errors in the session trace.
