# TASK-STANOK-CC-212: unfixable smoke — retries exhausted inside the container

test: tests/smoke_unfixable_test.py
impl: src/smoke_unfixable.py

run.sh: exists

## Context

CC-211 proved the recovery path (FAIL -> fix prompt -> PASS). This ticket
proves the EXHAUSTION path: a test that NO change to `src/` can make pass.
The machine must burn all its turns (initial + 2 local retries = 3) and the
run must end as VERIFY-FAIL. This is intentional: the failing test is the
point of the ticket, not a defect to work around.

## Requirement

1. Write `tests/smoke_unfixable_test.py` (pytest, `def test_*`) with exactly
   one test whose body is a deliberate contradiction: `assert False` (with a
   comment `# intentional: this test can never pass — CC-212`).
2. Write `src/smoke_unfixable.py` as a trivial module (e.g. `def noop() -> None: ...`)
   so the declared impl exists. It cannot make the test pass — by design.
3. After every `<verification_result status="FAIL">` block: do NOT change the
   test, do NOT change `scripts/run.sh`, do NOT delete anything. Fixing this
   test is impossible; the correct behavior is to leave the code as is.

## Acceptance criteria

- The run ends with the test still failing (the machine did not weaken or
  delete it). Final `src/smoke_unfixable.py` is a trivial valid module.
