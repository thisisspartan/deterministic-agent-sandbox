# TASK-STANOK-CC-129 — Kill-list 2.4: drop the "v4.2" banner and stale docstring claims

Supervisor-executed. Follows `specs/REVIEW-KISS-CLI-FIRST-2026-09-24.md` §8 (#4).

## Finding

Kill-list 3.4 removed the «Architectura v4.2» vocabulary from the READMEs but the
machine still announces it: `log(f"STANOK 4.2 RUNNER | …")` (`stanok.py:1424`) —
visible as line 1 of every `launcher.stdout.log`. The module docstring is also
stale: item 6 promises "Smart Diff Extraction: prioritized assert/diff search",
which CC-122 deleted (it is now a raw tail), and item 2 still advertises a "c5"
field mix. Documentation that contradicts the code is the same crutch class as
the README narrative — it makes the reader hunt for behaviour that is gone.

## Change

- `stanok.py:1424` banner → `STANOK RUNNER | …` (drop the frozen version number;
  the run commit is already in `summary.json` provenance).
- Module docstring `stanok.py:1-15`: drop "4.2 Production"; rewrite item 6 to
  "Verifier-output compression: dependency-noise filter + last-N tail"; keep the
  other items only if still true (check 1-5, 7 against the current code).

## Verification

`py_compile`; `doctor.sh` green. No test matched the banner string
(grep `STANOK 4.2` in `tests_harness/` = none).
