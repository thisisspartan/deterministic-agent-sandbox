# Code review: KV-cache efficiency + why CC-059 ran long (2026-09-10)

Scope: `~/darkcast` (root + `stanok/` submodule) as it stands after CC-059.
Focus: KV-cache efficiency, the last run's cost, and simple/lean improvements.

## TL;DR

- **KV cache is not the bottleneck — it is already near-optimal by design.** One
  continuous `ClaudeSDKClient` session, append-only context, no compaction, no
  prefix churn: 93.0% / 90.3% per-turn hit, 91.6% aggregate. The ~9% uncached is
  genuinely-new content (tool I/O, the retry block), not avoidable misses.
- **CC-059 was long because turn 2 generated 34,968 output tokens (~139K chars of
  reasoning, ~35K thinking tokens) to work around a test the model itself wrote
  against an explicit ticket prohibition — and that the TDD lock made unfixable.**
  Turn 2 = 1515s of 1782s (85%). Generation-bound, not cache-bound.
- The retry context was additionally poisoned by **binary node:test IPC garbage**
  in the failure dump.
- Improvements should target *reasoning/token efficiency and contract compliance*,
  not the cache. Four small, non-crutched changes below.

## 1. KV-cache review — verdict: optimal, leave it

What the design does right (`launcher/stanok.py`):
- ONE session across retries (`run_continuous_session`, 423-599): the retry is an
  in-session user turn, so the whole prefix stays in cache. This is the canonical
  2026 agentic pattern; do not change it.
- Append-only context; nothing rewrites the head. `CLAUDE_CODE_DISABLE_GIT_INSTRUCTIONS=1`,
  fixed tools, fixed model, fixed cwd → stable prefix.
- No compaction triggered: max context ≈53K vs `AUTO_COMPACT_WINDOW=123000` and
  server `n_ctx=123136`. Compaction (a prefix rewrite → full cache loss) never fires.
- Server `--parallel 1` + ctx-checkpoints: one writer, prompt cache reused.

Metric (`stanok.py:496-508`): `cache_read / (input + cache_read + cache_creation)`.
This server reports `cache_creation_input_tokens=0` always, and `input_tokens` are
genuinely-new prompt tokens, so the figure is a **prompt-cache read ratio**, not a
true hit/miss rate. It's a fine health metric (should stay >~85%), but don't
optimize against it: the residual "miss" is irreducible new content.

**Conclusion: no KV-cache work is warranted on the machine side.** The place where
KV *does* matter is the shared server's single slot (supervisor context resident —
`CONTEXT.md:33-35`): keep the supervisor <50k before launching and don't poll the
model mid-run. That rule is already documented and correct.

## 2. Why CC-059 was long — evidence

`evidence/cc059-fire-app-retry1/summary.json` + `events.jsonl`:

| Turn | wall | output tok | think chars | cache hit | num API turns |
|---|---|---|---|---|---|
| 1 | 262.6s | 7,222 | 20,880 | 93.0% | 22 |
| 2 | **1515.0s** | **34,968** | **139,432** | 90.3% | 9 |
| total | 1782s | 42,190 | 160,312 | 91.6% | 31 |

- Turn 2 is ~pure thinking: 139,432 chars ≈ 35K of the 35K output tokens. The
  actual code change was a tiny passthrough. ~23 tok/s generation → 1515s.
- Turn 1 failed `tests/fire_app.test.js:38` with `8 !== 0` (`actual: 8`), and the
  captured `actual` array is **node:test internal IPC/serdes binary** — the exact
  false-positive `tickets/TASK-STANOK-CC-059.md:60-67` had explicitly warned about
  and forbidden ("NOT by patching `process.stdout.write` … use a child process").
- The committed test still patches stdout (`tests/fire_app.test.js:33-40`),
  filtering only `'TAP version 13\n'`; real runner traffic slipped through.
- Turn 2 could not fix the test (test-lock.sh:52 denies writes to locked tests),
  so it hacked `src/main.js` ("thin synchronous passthrough … to fd 1") to make the
  broken test see zero writes. **The lock turned a bad test into a forced src crutch.**
- Turn-2 failure block fed to the model contained ~1.5KB of binary IPC junk
  (`\ufffd\u000f\u0000…`) — toxic context that plausibly drove the reasoning spiral.
- Nit: turn 2 `duration_api_ms=1,749,438` > `duration_ms=1,514,988` → SDK-level
  retries/overlap; worth a glance but not the main cost.

Root cause chain: **ticket's test rule ignored → bad test written → locked →
unfixable → src hack → 25 min of reasoning.** Nothing to do with KV.

## 3. Lean improvements (ranked; no over-engineering)

1. **Sanitize verifier feedback** (`_extract_smart_diff`, `stanok.py:240-274`).
   Drop/escape non-printable control bytes and NUL-heavy IPC blobs before the
   failure block reaches the model. ~5 lines; directly removes the poison that
   triggered turn-2's spiral, and keeps context small.
2. **Enforce the test contract instead of merely stating it.** Move the
   "no in-process stdout/stderr monkey-patching" rule from ticket prose into a
   deterministic PreToolUse guard on `tests/*.test.js` (same shift-left pattern as
   `malware-scan.sh`): deny writes containing `process.stdout.write =` /
   `process.stderr.write =` (or a reassignment of `.write`). Prevents the
   self-inflicted trap that cost this run 25 minutes. One grep, one hook entry.
3. **Unify test invocation.** `hooks/verifier.sh:90` runs `node "$TEST"`,
   `stanok.py:280` runs `node --test --test-force-exit`, `scripts/run.sh:47` runs
   `timeout 60 node "$f"`. Three runners → three behaviours → false confidence
   (the live hook can pass while the final gate fails). Pick `node --test <file>`
   for all three. Small, removes a real class of surprises.
4. **Progress-aware turn breaker (optional).** The wall-clock `TURN_TIMEOUT_S`
   (raised to 1800s for CC-057) let a 1515s reasoning spiral pass. A cheap
   progress check — interrupt and re-prompt *in-session* ("stop exploring, apply
   the smallest fix") when a turn accrues N output tokens / iterations without a
   green verifier step — preserves the KV cache and cuts the tail. Keep it a soft
   nudge, not a kill; only add if runs keep spiking.
5. **Hygiene:** remove the committed empty scratch files `tests/_diag.test.js`
   and `tests/_probe.test.js` (they match the `tests/**/*.test.js` gate glob and
   are machine-created cruft). Optionally ignore `tests/_*.test.js`.

## 4. What NOT to do

- Don't touch the single-session/KV design — it's the good part.
- Don't lower `TURN_TIMEOUT` back or add cache knobs; neither addresses the cause.
- Don't add a test-unlock mechanism for the model (weakens the Goodhart guard).
  Preventing the bad test (#2) is strictly better than healing it.
