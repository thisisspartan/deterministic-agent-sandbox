# TASK-STANOK-CC-070 — Harness correctness pass (#257, #258, proxy, dead code)

## 1. CONTEXT-ROT metric was cumulative (#258)
`_execute_turn()` iterated the response and `turn_usage.update(u)` for every
message. `receive_response()` ends on the `ResultMessage`, whose `usage` is the
**cumulative** usage over the turn's API calls; `.update()` let it overwrite the
per-call usage. So `inp + cache_read + cache_creation` was the whole turn
(1511122 / 213746 vs the real ~55k window).

Fix: `_execute_turn()` now returns `(turn_total, live_window)`:
- `turn_total` — `ResultMessage.usage` (cumulative; kept for session totals);
- `live_window` — the last `AssistantMessage.usage` (prompt size on the final
  API call = the true context window).
CONTEXT-ROT now fires on `live_context` (with fallback to the turn total if the
SDK omits per-call usage). Threshold: `context_rot_threshold()` = env
`STANOK_CONTEXT_ROT_TOKENS` else **80% of the compaction window** (123000 → 98400),
so a healthy ~55k turn no longer fires.

## 2. Nested-sandbox /tmp regression (#257)
The inner (native) sandbox re-binds its temp dir `/tmp/claude-<uid>` (cli.js
`AC()`), but `KC_` **silently skips a non-existent write path**; the outer
`--tmpfs /tmp` is empty, so the dir never existed → it stayed under the inner
`--ro-bind / /` → `read-only file system: /tmp/claude-1000/cwd-*`.
Fix: `sandbox-run.sh` now creates it in the outer namespace:
`BWRAP_ARGS+=(--dir "${CLAUDE_CODE_TMPDIR:-/tmp}/claude-$(id -u)")` right after
`--tmpfs /tmp`.
(The proposed rc=23 host-side mount-preflight was dropped: it would only re-check
paths `sandbox-run.sh` creates itself. End-to-end proof needs a real launch
through both layers — task #256.)

## 3. Dead proxy env in build_agent_env (#262 / audit 7)
The machine's tools are `Bash, Read, Write, Edit, Glob, Grep` — **no web tools**.
Its only outbound is the local API server, directly reachable. The
`http_proxy/https_proxy/all_proxy/no_proxy` copied from `P0-launch.sh` (the
*supervisor* session, which does have web tools) were vestigial and only forced
the local API call through the 8118 proxy. Removed the four keys plus the now-dead
`LOCAL_PROXY`/`NO_PROXY` constants and the README row. Native sandbox injects its
own proxy env into Bash commands when `network.allowedDomains` is set.

## 4. Sweep: dead code (#259)
- `launcher/stanok.py`: removed unused `import shlex`.
- `hooks/doctor.sh`: REMOVED the cloud-silence check (operator decision,
  2026-09-11). It grepped `evidence/cloud-review-*.jsonl`, but `cloud_review()`
  no longer exists in the runner and nothing writes those files (only the
  hardcoded `cloud_calls: 0` literal remains in `summary.json`) → the check could
  never fire. Also dropped the `DOCTOR_EXPECT_NO_CLOUD`/`DOCTOR_CLOUD_WINDOW_H`
  env and the README/setup.sh invocations. doctor is now **13 ok, 0 fail**.

## Files
- `stanok/launcher/stanok.py`, `stanok/sandbox-run.sh`, `stanok/README.md`

## Acceptance
- `py_compile` + `bash -n` clean.
- `context_rot_threshold()` → 98400 with the current 123000 window.
- `hooks/doctor.sh` on a clean tree: all ok (label-guard 15, fail-fast 20,
  dirty-tree 22, preflight-window 20, role-leak 24).
- A real smoke run: rc=0, verifier=PASS, and the turn log shows a `live window`
  ≈ 55k with **no** CONTEXT-ROT warning.
