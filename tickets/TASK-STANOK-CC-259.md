# TASK-STANOK-CC-259 (SMOKE, post-CC-258): k8s-only runtime note + its pin test

test: tests/k8s_only_runtime_test.py
docs: docs/k8s-only-runtime.md

run.sh: exists

## Context

This is a SMOKE ticket: its purpose is to exercise the launch pipeline end-to-end
after the Docker runtime path was removed (CC-258), under the gVisor runtime
(`STANOK_K8S_RUNTIME_CLASS=gvisor` is set on the launch by the supervisor).
Project stack: Python, pytest (`tests/**/*_test.py`), entrypoint `scripts/run.sh`
exists — use it as-is. stdlib only. Do not touch `src/`, `scripts/`, `launcher/`,
`k8s/`. No new dependencies.

## Requirement

`docs/k8s-only-runtime.md` — at most 40 lines, plain markdown, describing the
runtime contract as it works today:

- k8s is the ONLY runtime: the launcher dispatches host runs through
  `launcher/k8s.py` (worker Job + fresh-check Job on the local cluster); an
  explicit `STANOK_RUNTIME=docker` is refused with ENV-FAIL (rc=16, «docker
  runtime removed»);
- the tree reaches the Pod as a transport copy (ConfigMap), the Pod returns its
  evidence and `changes.patch` as one payload block; the host issues the final
  verdict (contract recompute + fresh check) and publishes
  `evidence/<label>/summary.json`; the patch lands on the live tree only on a
  clean verdict;
- the worker Pod's network is bounded by the rendered NetworkPolicy (only the
  model server and the Opik backend reachable); the fresh-check Job runs with
  no network at all;
- the image is delivered by digest from the node-local registry; the Job Pods
  run under the RuntimeClass the `STANOK_K8S_RUNTIME_CLASS` knob names.

Do not invent facts beyond the four points above.

## Tests (`tests/k8s_only_runtime_test.py`, at least 4 test functions)

The tests pin the docs file (read it relative to the repo root — the test file's
own location, `Path(__file__).resolve().parents[1] / "docs" / "k8s-only-runtime.md"`):

- the file exists and is valid UTF-8;
- it is at most 40 lines;
- it mentions all four contract points (substring checks: `STANOK_RUNTIME`,
  `changes.patch`, `NetworkPolicy`, `STANOK_K8S_RUNTIME_CLASS`);
- it does NOT present Docker as an available runtime: the strings `docker
  fallback` and `STANOK_RUNTIME=docker` may appear only in a refusal context —
  assert the line containing `STANOK_RUNTIME=docker` also contains `refused`
  or `removed`.

TDD: write the tests first (red: the docs file does not exist), then write the
docs file to green. No other files.
