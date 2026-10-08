# TASK-STANOK-CC-211: negative smoke — fix-prompt loop inside the container

test: tests/smoke_neg_test.py
impl: src/smoke_neg.py

run.sh: exists

## Context

CC-210 proved the happy path through the sandbox (host -> docker -> container
gates -> agent -> verify -> PASS). This ticket proves the NEGATIVE path of
the verdict pipeline inside the container: verify_gate FAIL -> the machine
receives a `<verification_result status="FAIL">` fix prompt -> fixes src/ in
the next turn -> PASS. The two-turn shape is the point of the ticket.

## Requirement (two-stage discipline — follow it exactly)

1. **Turn 1:** write `tests/smoke_neg_test.py` (pytest, `def test_*`) for a
   function `add(a: int, b: int) -> int` in `src/smoke_neg.py` (assert
   `add(2, 3) == 5`, `add(0, 0) == 0`, negative operands). Then implement
   `src/smoke_neg.py` with an INTENTIONAL off-by-one bug: `return a + b + 1`.
   Do NOT fix the bug in turn 1 — the external verifier must see a FAIL.
2. **Fix turn:** after the external verifier reports FAIL (the
   `<verification_result status="FAIL">` block arrives), fix ONLY
   `src/smoke_neg.py` so that `add` returns `a + b`. Do not change the tests.

## Acceptance criteria

- Final state: `add(a, b) == a + b`; tests unchanged from turn 1.
- `scripts/run.sh test --all` -> rc=0 at the end.
