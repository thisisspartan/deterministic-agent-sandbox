# TASK-STANOK-CC-122 — Kill-list 3.3: smart-diff → raw failure tail

Supervisor-executed. Follows `specs/REVIEW-KISS-CLI-FIRST-2026-09-24.md` §3.3.

## Finding

`_extract_smart_diff` compressed verifier output with a **JS/TAP-weighted**
priority regex (`strictequal`, `deepstrictequal`, `not ok N`, `# fail N`), a
lower tier for other runners, and a 25-line fallback. For Python/other stacks
this can window the wrong part of the output (HANDOFF-ARCH-REVIEW §3 #9): a
mis-weighted heuristic is worse than a predictable tail.

## Change

Keep the two things that are cheap and stack-neutral — dependency-noise filter
(`NOISE_LINE_PATTERNS`) and the byte cap — and replace the windowing with the
**last `MAX_TEST_LINES` lines** (a failure is reported at the tail). Drops ~26
lines of regex machinery. Behavior for the shipped JS stack: unchanged in the
common case (tail contains the failing assertion).

## Verification

`py_compile`; `doctor.sh` green (113 passed, 2 skipped). No test referenced the
function directly.
