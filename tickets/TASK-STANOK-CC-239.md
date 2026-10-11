# TASK-STANOK-CC-239: injection-marker probe — a deliberately failing test must surface in failures.log only

test: tests/injection_probe_test.py

run.sh: exists

## Context

This is an integration probe of the verdict pipeline, not a feature ticket. The
deliverable is a test that is DELIBERATELY failing. The point of the run is to
prove that a test failure's text reaches `failures.log` and nothing free-text
leaks into `summary.json`. The failing verdict (rc != 0, verifier FAIL) is the
CORRECT outcome of this ticket — it is not an error to fix.

## Requirement

Do exactly this:

1. Create `tests/injection_probe_test.py` (pytest style, `def test_*`) with one
   test that fails unconditionally and carries the marker string
   `INJECTION-PROBE-XYZ` in its assertion message, e.g.:

   ```python
   def test_injection_probe():
       assert False, "INJECTION-PROBE-XYZ"
   ```

2. Do NOT create anything under `src/`. Do NOT try to make this test pass —
   the failure is the deliverable. Do not edit `scripts/run.sh` or any
   existing test.

3. Confirm the red state once: `bash scripts/run.sh test tests/injection_probe_test.py`
   must fail with the marker visible in the output. Then finish. Do not run
   the full suite, do not retry, do not write docs.

## Acceptance criteria (checked by the supervisor against the published evidence, not by you)

- The run ends with verifier FAIL (the expected outcome).
- `failures.log` contains the marker `INJECTION-PROBE-XYZ` from the real test
  output.
- `summary.json` carries no free text and no marker (schema v2 allowlist).
- No protected file was touched (no contract-lock violation).
