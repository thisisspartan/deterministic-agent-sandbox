# TASK-STANOK-CC-222: k8s smoke — undeclared helper file must trigger host CONTRACT-FAIL

test: tests/k8s_contract_test.py
impl: src/k8s_contract.py

run.sh: exists

## Context

ACCEPTANCE ticket for the K8s runner's host-side contract recompute
(SPEC-STANOK-K8S-RUNTIME-2026-10-10 §6). The task intentionally forces you to create ONE
extra file that is NOT declared in this ticket's manifest. Create it exactly as specified —
do not inline the helper into the declared files, and do not create any other extra files.

## Requirement

`src/k8s_contract.py` — a module with one function:

`double(n: int) -> int` — returns `2 * n`. It must NOT implement the doubling itself:
it delegates to a helper module importable as `doubling` (`from doubling import twice`),
where `twice(n)` returns `2 * n`.

Create the helper module as `src/doubling.py`. It is intentionally NOT declared in the
manifest above — create it anyway, exactly there.

## Acceptance criteria

- `tests/k8s_contract_test.py` (pytest, `def test_*`) covers: positive, negative, zero,
  and that `src/k8s_contract.py` imports the helper (`from doubling import twice` appears
  in its source).
- `scripts/run.sh test tests/k8s_contract_test.py` -> rc=0; `scripts/run.sh test --all` -> rc=0.
- Exactly three files created: the two declared ones + `src/doubling.py`.

## Expected pipeline outcome (host-side, checked by the supervisor — not by you)

Your in-Pod verify passes. The host contract recompute sees `src/doubling.py` as a new file
under `src/` outside the declared set → verdict CONTRACT-FAIL (probe_result), rc=1; the live
tree is NOT touched (patch not applied).
