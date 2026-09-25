# TASK-STANOK-CC-162: Supervisor long-term memory (persistent facts in CONTEXT.md)

Executor: operator/supervisor (supervisor-zone: `CONTEXT.md`, `CLAUDE.supervisor.md` — NOT a machine ticket, no launch).

## Problem (incident 2026-09-25)

The supervisor "forgot" that the www.js work on `192.168.8.131` had already been
done earlier the same day — the fact lived only in a previous session's
transcript. `CONTEXT.md` already carries durable server facts (SSH user `llm@`,
log API `:3000/api/logs`, topology) and is read at session start
(CLAUDE.supervisor.md §1), but it has NO dated session-log section and NO
discipline for appending what was DONE in a session — so work products
(bugs found, fixes specified, status) are lost on compact/restart.
Side note from the incident: the failed SSH probe used `hermes@192.168.8.131`
(wrong user — CONTEXT.md says `llm@`); access is likely fine with the right user.

## Requirements

1. Add a section to `/home/hermes/darkcast/CONTEXT.md`:
   ```
   ## Persistent facts (session log)
   ```
   Format: one dated bullet per significant event —
   `- YYYY-MM-DD — <fact: system, what was done/decided, access details, open threads>`.
   Newest first. This is the supervisor's long-term memory; transcripts are not.
2. Seed the section with the www.js entry (facts from the 2026-09-25 sessions):
   - `~/www.js` on `192.168.8.131` — llama.cpp server log monitor (web dashboard).
   - Bug found & fix specified (2026-09-25): in section `// 4. KV REUSE`,
     `fromRam` was ALWAYS false — `isFromHostRam` waits for the
     "found better prompt" line which llama.cpp does not print in a normal
     single-slot dialogue, and `initNewTask()` never copies the flag into
     `state.task.fromHostRam` → the ternary always picked 'KV REUSE VRAM'.
     Physics: context checkpoints (`--ctx-checkpoints 24 --cache-ram 30720`)
     live exclusively in Host RAM; "restored context checkpoint (size = 477 MiB)"
     = RAM→VRAM restore; a true hot-VRAM hit is the separate `cached n_tokens =`
     branch (4b). Fix: hardcode tag `'KV REUSE RAM'`, source `'Host RAM'`,
     keep the in-place-hit overwrite logic.
   - Access: `ssh hermes@192.168.8.131` → `Permission denied (publickey,password)`;
     per CONTEXT.md the correct user is `llm@` — retry with `llm@` before
     asking the user for credentials.
   - Status: fix specified but NOT yet applied/verified on the server.
3. Add one line to `CLAUDE.supervisor.md` §1 (after the CONTEXT.md item):
   "After each significant session event (external-system work, decisions,
   access/credentials, open threads) append a dated entry to the
   `## Persistent facts (session log)` section of `CONTEXT.md` — transcripts
   are not memory."

## Acceptance criteria

- `CONTEXT.md` contains the `## Persistent facts (session log)` section with the
  www.js entry (system, bug, fix, access problem, status).
- `CLAUDE.supervisor.md` §1 contains the append-discipline line.
- Next session start: reading `CONTEXT.md` (already mandatory per §1) surfaces
  the www.js state without any transcript lookup.

## Non-goals

- No new files (no MEMORY.md) — CONTEXT.md is the single store.
- No automatic/transcript-scoping mechanism; the discipline is procedural.
- No changes to `stanok/`.
