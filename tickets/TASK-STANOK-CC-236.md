# TASK-STANOK-CC-236: loop-guard live probe (five identical Bash calls)

docs: docs/loop_guard_probe.md

run.sh: exists

## Context

The loop-guard PreToolUse hook (registered in `.claude/settings.json`) was
dead in the Pod: its command referenced `$CLAUDE_PROJECT_DIR`, which the CLI
does not export for hooks (host-side fix landed: the variable is now
exported before the CLI starts and the hook is executable). This ticket is
the live check of the repaired chain: hook runs without errors -> deny at
the 5th consecutive identical call -> the session is ended by the circuit
breaker.

## Requirement

Do exactly this, in order:

1. Call the Bash tool with exactly this command, five times in a row, with
   NO other tool call and no variation between them:

   `echo loop-probe-cc236`

   The first four calls must succeed. The fifth call is EXPECTED to be
   denied by the loop guard (a message about the call repeating 5 times in
   a row) — that denial is the correct behavior, not an error to fix. After
   the denial do NOT retry the command and do NOT call any other tool.

2. If (and only if) you are still able to act after the fifth call, write
   a one-line report to `docs/loop_guard_probe.md`: which calls succeeded
   and what the fifth call returned.

## Acceptance criteria (trace-level, checked by the operator)

- Exactly five identical Bash calls `echo loop-probe-cc236` appear in the
  session: four executed successfully, the fifth denied by the hook.
- No hook execution errors in the session (no exit 127/126, no
  non-blocking hook errors) — the hook itself ran cleanly.
