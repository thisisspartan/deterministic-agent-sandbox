# TASK-WWWJS-08: lifecycle/telemetry separation + history row contract

## Context
www.js dashboard @192.168.8.131 (`/tmp/www.js`, deploy to `llm@192.168.8.131:~/www.js`).
Architecture review verdict (2026-09-26). Scope: TARGETED fix (user-approved) — no
normalized-event/reducer rewrite, no multi-task Map (parallel=1, YAGNI).

## Bug (live-proved): stage stuck at MTP after DONE
`addEvent()` (`www.js:114`) sets `state.currentStage = stage` for EVERY event.
The `draft acceptance` (MTP) line arrives AFTER `eval time` (DONE) — so:
DONE (`currentStage='DONE'`, setTimeout 1500ms checks `=== 'DONE'`) → MTP line
overwrites `currentStage='MTP'` → timeout condition false → **never resets to
IDLE**. Live: `stage: MTP`, `is_processing: false`, log `all slots are idle`.

## Fix 1: lifecycle/telemetry separation
- `addEvent(stage, tag, title, detail, explicitTaskId = null, lifecycle = true)` —
  when `lifecycle === false`, do NOT touch `state.currentStage`.
- MTP branch (`draft acceptance`) → `addEvent('MTP', ..., false)` (telemetry).
- All other addEvent calls stay lifecycle (INPUT, PREFIX, KV_RESTORE, PREFILL,
  DECODE, DONE, CANCEL, STALL_WARN).

## Fix 2: robust IDLE reset
- New state field `_awaitingIdle: false`.
- DONE (`eval time`) and CANCEL branches: `state._awaitingIdle = true` (instead of
  relying on `currentStage === 'DONE'` in the timeout).
- `initNewTask()`: `state._awaitingIdle = false` (a new task cancels the pending reset).
- Both 1500ms timeouts: `if (state._awaitingIdle && !state.is_processing) {
  state._awaitingIdle = false; state.currentStage = 'IDLE'; broadcastState(); }`.

## Fix 3: history row contract (no semantic mixing)
`pushHistory` base row becomes:
- `lcp: state.task.lcpTokens` (LCP match — separate from KV)
- `kvReuse: state.task.kvRestoredTokens` (NO `|| lcpTokens` fallback)
- `kvSource: state.task.kvSource` — `'vram'` (hot slot, `cached n_tokens` first>0),
  `'ram'` (restored context checkpoint), `null` (none)
- `prefill: state.task.prefillTokens || state.task.deltaTokens`
- `prefillSource: state.task.prefillTokens ? 'measured' : 'estimated'`
- (existing fields unchanged: id/input/decode/speed/total/isTruncated/mtp*/time)

Task state: new `kvSource: null` in `freshTaskState()`; set `'ram'` in the
`restored context checkpoint` branch, `'vram'` in the hot-slot `cached n_tokens`
branch, reset `null` in `forcing full prompt re-processing`.

## Fix 4: UI
History table: KV REUSE column shows source marker (VRAM/RAM, dim when 0);
PREFILL column renders `~N` when `prefillSource === 'estimated'`.

## Acceptance
1. `node --check` OK.
2. New local test `/tmp/test-wwwjs-lifecycle.js` on real lines:
   - DONE → late MTP line: `currentStage` stays 'DONE' (not 'MTP');
   - after 1500ms-equivalent (call the timeout logic via state flags):
     `_awaitingIdle && !is_processing` → 'IDLE';
   - new task while `_awaitingIdle` → flag cleared, no IDLE clobber;
   - history row: `lcp`/`kvReuse`/`kvSource`/`prefill`/`prefillSource` correct for
     a RAM-restore task and a cold task.
3. Regressions green: kvcached 12, lcp 13, ngram 10, ram-est 22, fresh-task 13,
   pushhistory 23 (pushhistory row-shape checks updated for the new contract).
4. Deploy: backup `~/www.js.bak-wwwjs08` → restart → live: HTTP 200, after a task
   completes the stage returns to IDLE (not stuck at MTP).
