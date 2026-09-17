# TASK-STANOK-CC-001 — NO-OP status-fields fix (probe_result override)

Harness fix (supervisor-applied, not a machine task). Closes the last open
seam from the harness review: a successful NO-OP run was mislabeled by the
status fields.

## Problem
`_status_fields` (stanok.py) is fail-closed on `rc==0 AND verifier=="PASS"`.
The NO-OP branch returns `rc=1`, so a SUCCESSFUL no-op got `c5=FAIL` +
`review_verdict=DEFECT` — only `probe_result` was overridden to
`NO-OP-PASS`. rc=1 is polysemous (NO-OP vs exhausted-retries), so a rc-keyed
RC_TABLE row cannot express two field-sets for one rc.

## Fix
Extend the existing `probe_result` override in `build_summary` (NOT a new
RC_TABLE row, NOT a new rc): when `probe_result == "NO-OP-PASS"`, set
`c5="PASS"` (verify_gate really passed — a fact) and `review_verdict="NOOP"`
(the third outcome; the L1 contract has no strict review_verdict enum —
verdicts run on rc+verifier only — so free-form is safe). Added an explicit
comment at the edit site: rc=1 is polysemous, disambiguate by probe_result
not rc; do not restore a pure rc->fields table.

## Scope
- `stanok/launcher/stanok.py` — `build_summary` only (2 conditional
  assignments + comment).
- `rc`, `RC_TABLE`, and the supervisor contract are UNTOUCHED.

## Verification
- `python3 -m py_compile launcher/stanok.py` → SYNTAX OK.
- Confirmed against the `noop-verify` run (rc=1, verifier=PASS,
  probe_result=NO-OP-PASS, writes=0).
