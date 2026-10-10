# TASK-STANOK-CC-221: k8s smoke — happy path end-to-end (payload → evidence → patch → fresh green)

test: tests/k8s_smoke_test.py
impl: src/k8s_smoke.py

run.sh: exists

## Context

This is an ACCEPTANCE ticket for the new K8s-Job runner (SPEC-STANOK-K8S-RUNTIME-2026-10-10).
The task itself is deliberately trivial: its purpose is to exercise the full pipeline —
payload emission from the Pod, host extraction into `evidence/`, patch application, fresh-check
Job. Do the task honestly and normally; do not try to "help the pipeline" beyond the task.

## Requirement

`src/k8s_smoke.py` — a module with one function:

`add(a: int, b: int) -> int` — returns the sum of its two arguments.

## Acceptance criteria

- `tests/k8s_smoke_test.py` (pytest, `def test_*`) covers: positive numbers, negative
  numbers, zero identity (`add(0, x) == x`), commutativity (`add(a, b) == add(b, a)`).
- `scripts/run.sh test tests/k8s_smoke_test.py` -> rc=0 after the implementation;
  `scripts/run.sh test --all` -> rc=0.
- Create NO files other than the two declared above.

## Expected pipeline outcome (host-side, checked by the supervisor — not by you)

Payload block accepted (nonce match) → `evidence/<label>/` contains summary.json +
changes.patch → contract clean → fresh Job green → final verdict PASS, rc=0, patch applied
to the live tree.
