# TASK-WWWJS-07: cached n_tokens state machine + LCP exact tokens

## Context
www.js dashboard @192.168.8.131 (`/tmp/www.js` working copy, deploy to `llm@192.168.8.131:~/www.js`).
Review verdict (2026-09-26) proved 2 logic bugs + 1 edge case in the log parser.

## Bug 1 (P0): `cached n_tokens` misread as KV reuse on cold start
Current (`www.js:266-278`): the first NON-ZERO `cached n_tokens` after `new prompt`
fires `KV REUSE VRAM` — but on a cold start the first line is `cached n_tokens = 0`
and subsequent lines (1024, 2048, ...) are PREFILL PROGRESS of the current task,
not restored KV. Real log (task 38): `new prompt ... 34067` → `cached 0` →
`cached 1024` → `cached 2048` → `prompt processing ... 3072` → `prompt eval time
= 42126.26 ms / 34067 tokens` (full prefill, zero reuse). Hot slot (task 457):
`new prompt ... 35552` → `cached 35009` (first value already non-zero = real hit).

Fix: remember the FIRST `cached n_tokens` value after `new prompt`
(new field `cachedFirstSeen: false` in `freshTaskState()`). Only that first value
may trigger `KV REUSE VRAM`, and only if `> 0`. All subsequent `cached n_tokens`
lines are prefill progress — they must NEVER modify `kvRestoredTokens` /
`deltaTokens` / emit events.

## Bug 2: LCP token count clobbered by `f_sim_best`
Current (`www.js:197-208`): `f_sim_best =` line carries no `(N/M)` count and the
`line.includes('sim_best')` tiebreaker force-overwrites `pendingLcp` with
`tokens = 0`. Then `initNewTask` (`www.js:153`) reconstructs
`Math.round(promptTokens * pendingLcp.ratio)` from the ROUNDED ratio:
task 457: `checking sim = 0.985 (35009/35552)` + `f_sim_best = 0.985` →
`round(35552 * 0.985) = 35019` instead of exact 35009 (+10; up to −42 on 96k ctx).

Fix: on a `f_sim_best` line, keep the previous `pendingLcp.tokens` ONLY when
`pendingLcp.ratio === ratio` (same candidate — the checking-sim line of the
selected prompt); otherwise `tokens = 0` (fallback in `initNewTask` stays as-is).
Exact `(N/M)` tokens from `checking sim` lines are never discarded.

## Bug 3 (edge): monitor attached mid-task → phantom SYS KV event
`isForeignTask()` (`www.js:106-109`) returns false when `state.task.id === null`,
so a `cached n_tokens` line arriving before the first `new prompt` (monitor
started mid-task) sets `kvRestoredTokens` on a null-id task and `addEvent` tags
it `SYS`. Fix: guard the `cached n_tokens` branch with `if (!state.task.id) return;`
(a `cached` line can never legitimately precede `new prompt`).

## Acceptance
1. `node --check /tmp/www.js` OK.
2. New local test `/tmp/test-wwwjs-kvcached.js` on real log lines:
   - cold start (0 → 1024 → 2048): NO KV event, `kvRestoredTokens === 0`,
     `deltaTokens === totalPrompt`;
   - hot start (first `cached 35009`): KV REUSE VRAM event, `kvRestoredTokens === 35009`;
   - subsequent cached lines never modify `kvRestoredTokens`;
   - `cached` line with `state.task.id === null` → no event, no state change.
3. LCP test extended (`/tmp/test-wwwjs-lcp.js`): `checking sim = 0.985 (35009/35552)`
   + `f_sim_best = 0.985` → `lcpTokens === 35009` (NOT 35019); existing
   ratio-mismatch case (0.984/97074 + fbest 0.950) still → tokens 0 → 95000.
4. Regressions green: ngram 10, ram-est 22, fresh-task 13, pushhistory 23, lcp (extended).
5. Deploy: `scp` → backup `~/www.js.bak-wwwjs07` → `node --check` →
   `/tmp/restart-wwwjs.sh` → live: HTTP 200, `/api/state` sane.
