# TASK-STANOK-CC-126 — Kill-list 2.1: drop the false PREFIX-BREAK warn on turn 1

Supervisor-executed. Follows `specs/REVIEW-KISS-CLI-FIRST-2026-09-24.md` §8 (#1).

## Finding

`stanok.py:1193` — `elif inp > 4000:` fires when `prev_inputs` is empty, i.e.
**always on turn 1**. A prompt-size comparison against a constant "baseline" is
not a prefix-break: there is no previous turn to break the prefix from.

Trace: all three runs log `[PREFIX-BREAK WARN] turn 1 input_tokens=… > 4000
baseline` (`cc119-fire16/launcher.stdout.log:21`, `-retry2:11`) and write
`"prefix_break": true` into `summary.json` — a signal field that is true on every
run is noise, and it trains the operator to ignore the alarm.

## Change

Delete the turn-1 `elif` branch. The inter-turn check (`inp > 2 * median(prev)`)
stays; it is the actual metric and only runs from turn 2, where a baseline exists.

## Verification

`py_compile`; `doctor.sh` green. No test asserted the turn-1 branch
(grep `prefix_break` in `tests_harness/` = none).
