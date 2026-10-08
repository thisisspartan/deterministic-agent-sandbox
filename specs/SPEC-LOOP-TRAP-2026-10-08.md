# SPEC-LOOP-TRAP — circuit breaker for repeated identical tool calls

Status: IMPLEMENTED (CC-207, stanok `73b90f6`, 2026-10-08). This file records
the contract; the incident analysis is `specs/REVIEW-LOOP-TRAP-CC204-2026-10-07.md`
(findings-only, CC-204-retry3: 31 identical Reads, 22 ineffective blocks).

## Contract

1. Machine-side hook (in-session, `launcher/session.py`): counts consecutive
   IDENTICAL tool calls (name + input hash). At THRESHOLD=5 the call is
   DENIED and a JSON marker is written to `STANOK_LOOP_TRAP_FILE` =
   `LOG_DIR/<label>/loop-trap.json` (tool / hash / n).
2. `_execute_turn` reads the marker mid-turn -> the turn is interrupted and
   the run terminates with `probe_result: "LOOP-TRAP"`, rc=1. NO fix prompt,
   NO local retries (the marker is cumulative — a retry would re-trap).
3. `summary.json` carries the `loop_trap` field (tool/hash/n). Supervisor
   protocol: `CLAUDE.supervisor.md` §3 B2 — defect class of the TICKET, not
   of the code: refine the requirements, relaunch as `<label>-retry1`
   (counts toward the 3-attempt limit); never relaunch the same ticket
   unchanged.
4. Deliberate divergence (operator decision 2026-10-08): the supervisor's own
   hook copy `darkcast/.claude/hooks/loop-guard.py` keeps THRESHOLD=10 and
   writes no marker — the two copies are intentionally NOT synced.

## Non-goals

- Not a quality judge: only exact repetition is trapped.
- Not a KV-cache fix: the trap bounds the damage of a loop, it does not
  prevent one (ticket authoring is the prevention).
