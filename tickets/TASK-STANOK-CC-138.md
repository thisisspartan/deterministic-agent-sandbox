# TASK-STANOK-CC-138 — delete the `node_modules` noise filter (raw tail only)

Supervisor-executed (`launcher/` is RO in the container). Follows
`specs/AUDIT-STANOK-2026-09-24.md` §4 row 6 (§1#1), the last row of the ACTION
PLAN. Audit calls it CC-137; the operator's live numbering put T5 at CC-137
(CC-136 was the `:ro` half split out of T4), so the filter is CC-138.

## Finding

`_extract_smart_diff` carried `NOISE_LINE_PATTERNS = ("node_modules/",)` and a
substring filter that dropped any line containing it. The docstring directly
above the filter claimed "No pattern heuristics" — the code contradicted it.
It was a JS-era W10 remainder: the compressed output goes into the fix prompt,
so a substring filter can hide exactly the dependency line the model needs, the
same failure mode CC-122 removed from the JS/TAP priority regex. The audit's
§3.3 decision (already implemented by CC-122) is "the raw tail is the contract".

## Change

- `stanok.py`: `NOISE_LINE_PATTERNS` and its W10 comment deleted; the
  `[... if not any(p in ln ...)]` comprehension becomes
  `lines = raw_text.strip().splitlines()`; the `if not lines:` fallback (which
  existed only because the filter could empty the list) deleted. The last-N-lines
  window and the byte-limit truncation are untouched.
- Both docstrings made true: the module header item 6 and the function docstring
  now say "last-N raw tail, no pattern heuristics at all".
- New `launcher/tests_harness/test_smart_diff_tail.py` (4 tests): a
  `node_modules/` line survives verbatim; `NOISE_LINE_PATTERNS` no longer exists;
  the window keeps exactly the last `MAX_TEST_LINES` lines with the
  `... [N lines skipped above] ...` marker; the byte truncation still fires.

## Verification

- `py_compile` (stanok.py).
- `bash hooks/doctor.sh` — **147 passed, 0 skipped on a clean tree**
  (143 + 4; no test weakened). The new fixture's tail contains a
  `node_modules/` line, which is exactly the audit's stated check.
- The compression still bounds the fix prompt (60 lines / 4096 bytes), so
  removing the filter does not let an unbounded tail through.

## Non-goals / residuals

- Only the substring filter is gone. `_extract_smart_diff` still trims to the
  last 60 lines / 4096 bytes — that bound is the compression contract, not a
  pattern heuristic.
- The `NOISE_LINE_PATTERNS` registry is deleted rather than kept empty: there is
  no second consumer to preserve, and an empty registry is dead state.
- Historical specs (`STATUS.md`'s P6/W10 notes, the audit itself) still mention
  the filter; they are point-in-time documents and were not rewritten.

## ACTION PLAN status

This closes §4 row 6. All six rows are now done under the operator's numbering:
CC-132, CC-133, CC-134, CC-135 (T4), CC-136 (T4b `:ro` half), CC-137 (T5),
CC-138 (this). Remaining unrequested work in the audit is **Appendix A's five
UNVERIFIED items** (none of them has been approved or run).
