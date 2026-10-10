# TASK-STANOK-CC-227: k8s smoke under DNS blackout — happy path end-to-end (Package 1 closing gate)

impl: src/k8s_net_smoke.py
test: tests/k8s_net_smoke_test.py

run.sh: exists

## Context

This is an ACCEPTANCE ticket for the K8s-Job runner (SPEC-STANOK-K8S-RUNTIME-2026-10-10)
re-run under the NEW Package 1 NetworkPolicy: the worker Pod now has a FULL DNS egress
blackout (no kube-dns rule; egress only to the literal-IP /32 endpoints on port 8080).
The task itself is deliberately trivial: its purpose is to exercise the full pipeline —
payload emission from the Pod, host extraction into `evidence/`, patch application, fresh-check
Job — while the worker reaches the model server and the tracing endpoint by IP literal only.
Do the task honestly and normally; do not try to "help the pipeline" beyond the task.

## Requirement

`src/k8s_net_smoke.py` — a module with one function:

`mul(a: int, b: int) -> int` — returns the product of its two arguments.

## Acceptance criteria

- `tests/k8s_net_smoke_test.py` (pytest, `def test_*`) covers: positive numbers,
  negative × positive (sign), zero identity (`mul(0, x) == 0`), identity with one
  (`mul(1, x) == x`), commutativity (`mul(a, b) == mul(b, a)`).
- `scripts/run.sh test tests/k8s_net_smoke_test.py` -> rc=0 after the implementation;
  `scripts/run.sh test --all` -> rc=0.
- Create NO files other than the two declared above.

## Expected pipeline outcome (host-side, checked by the supervisor — not by you)

Payload block accepted (nonce match) → `evidence/<label>/` contains summary.json +
changes.patch → contract clean → fresh Job green → final verdict PASS, rc=0, patch applied
to the live tree. The run's timing fields (elapsed_s / total_turn_elapsed_s) are recorded
by the supervisor as the startup-time measurement.
