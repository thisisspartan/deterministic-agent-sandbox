# TASK-WWWJS-09: honest donut anatomy after DONE/IDLE + CUMULATIVE badge

## Context
www.js dashboard @192.168.8.131 (`/tmp/www.js`, deploy to `llm@192.168.8.131:~/www.js`).
Review verdict 2026-09-26 (user-pasted, verified against code). Scope: FULL (user-approved).

## Bug 1 (live-proved): DONE/IDLE donut lies about KV REUSE
`renderState()` (`www.js:976-981`):
```js
let rawUsed = cachedVal + deltaVal + genVal;
if (stage === 'DONE' || stage === 'IDLE') {
  cachedVal = rawUsed; deltaVal = 0; genVal = 0;
}
```
Legend (`:1042-1044`) repeats the same override. After DONE the whole used
context (reuse+prefill+decode) is labeled **KV REUSE** — false: only the
restored part was reuse. Motive was cosmetic (full green ring in idle), but
for an educational dashboard the label is a lie.

## Bug 2: LCP≠KV fallback still in the donut (`www.js:972`)
`let cachedVal = num(t.kvRestoredTokens || t.lcpTokens, 0);` — the same
`|| lcpTokens` fallback WWWJS-08 removed from history. Cold task with LCP
similarity but no real KV restore shows lcpTokens as "KV REUSE". `kvSource`
(vram/ram, added in WWWJS-08) is unused by the donut.

## Bug 3: NGRAM-MOD panel unlabeled cumulative
`statistics ngram-mod:` → global `state.ngram` (never reset per task) =
server-wide cumulative since server start, while MTP (197/211) is per-task.
Panel title `NGRAM-MOD SPEC` (`:799`) has no CUMULATIVE marker → illusion
that one request generated a million tokens.

## Fix 1: remove the lumping
- Delete the `if (stage === 'DONE' || stage === 'IDLE') { cachedVal = rawUsed; ... }`
  block — in DONE/IDLE the donut and legend keep the last task's anatomy
  (KV REUSE / PREFILL / DECODE separate).
- Legend values: always `cachedVal` / `deltaVal` / `genVal` (no stage override).
- Donut center (`core-pct`): `CONTEXT: N (pct%)` — the sum, labeled as total
  context used, not as reuse.

## Fix 2: honest cached segment
- `cachedVal = num(t.kvRestoredTokens, 0)` — NO `|| lcpTokens` fallback.
- Legend KV REUSE row: source marker from `t.kvSource` (VRAM/RAM, dim, like
  the history column).

## Fix 3: CUMULATIVE badge
- `NGRAM-MOD SPEC` → `NGRAM-MOD SPEC <span ...>(CUMULATIVE)</span>` (dim,
  small, same style as the verdict mockup).

## Acceptance
1. `node --check` OK.
2. grep: no `cachedVal = rawUsed`, no `stage === 'DONE' || stage === 'IDLE' ?`
   overrides in the legend, no `kvRestoredTokens || t.lcpTokens` in renderState.
3. Regressions green (parser untouched): kvcached 12, lcp 13, ngram 10,
   ram-est 22, fresh-task 13, pushhistory 26, lifecycle 21.
4. Deploy: backup `~/www.js.bak-wwwjs09` → restart → live: HTTP 200,
   `(CUMULATIVE)` in served HTML, after a task completes the legend shows
   separate KV REUSE / PREFILL / DECODE values (not one lumped REUSE).
