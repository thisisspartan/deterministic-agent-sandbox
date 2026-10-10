# TASK-STANOK-CC-233: in-Pod proof that the Pod-only test guard is active in both Pods

impl: src/pod_guard.py
test: tests/pod_guard_test.py
docs: docs/pod_guard.md

run.sh: exists

## Context

The runner Pods (worker and fresh-check) now set the environment variable
`STANOK_IN_POD=1`; test files use it to skip Pod-only invariants on the host
and to run them inside the Pod. Your task is a live proof, from INSIDE the
Pod, that the marker is present and the designated writable zone works — the
smallest possible acceptance probe for that mechanism. The task payload is
deliberately small; its purpose is the proof.

## Requirement

`src/pod_guard.py` (stdlib only — `os`, `secrets`):
- `in_pod()` -> `True` if the environment variable `STANOK_IN_POD` equals
  `"1"`, otherwise `False` (absent or any other value -> `False`).
- `write_ok(path)` -> `True` if a uniquely-named file can be created and
  removed inside `path`; `False` otherwise (any `OSError`).

`tests/pod_guard_test.py` (pytest, `def test_*`):
1. `test_in_pod_marker_parsing` (runs everywhere): with the environment
   monkeypatched — unset -> `in_pod() is False`; `"1"` -> `True`;
   `"0"` -> `False`.
2. `test_marker_present_in_pod` (Pod-only, same skipif pattern as
   `tests/ro_root_smoke_test.py`: skip unless `STANOK_IN_POD` is set):
   `in_pod() is True` — the marker must be present in the running Pod.
3. `test_work_zone_writable` (Pod-only, same pattern):
   `write_ok("/stanok-work") is True` — the emptyDir must accept writes.

## Acceptance criteria

- `scripts/run.sh test tests/pod_guard_test.py` -> rc=0; `scripts/run.sh test --all` -> rc=0.
- Create NO files other than the three declared ones.
