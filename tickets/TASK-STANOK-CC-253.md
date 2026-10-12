# TASK-STANOK-CC-253 (SMOKE, gVisor trial): one-page note on the runtime-class knob

docs: docs/gvisor-trial.md

run.sh: exists

## Context

This is a SMOKE ticket: its purpose is to exercise the launch pipeline end-to-end
under the gVisor runtime (`STANOK_K8S_RUNTIME_CLASS=gvisor` is set on the launch
by the supervisor). It adds NO code and NO tests. The only deliverable is one
short documentation file.

## Requirement

`docs/gvisor-trial.md` — at most 40 lines, plain markdown, describing the
runtime-class contract as it works today:

- the launcher renders `runtimeClassName` on the Job Pod ONLY when the env
  `STANOK_K8S_RUNTIME_CLASS` is set; unset/empty = RuntimeDefault (runc),
  the previous behavior;
- the value `gvisor` maps to the cluster RuntimeClass `gvisor` (handler runsc);
  the fresh-check Pod runs under the same class;
- the launch preflight refuses to start a run when the knob names a RuntimeClass
  that does not exist in the cluster (rc=16, the fix is named);
- the image is delivered by digest from the node-local registry regardless of
  the runtime class.

Do not invent facts beyond the four points above. Do not touch `src/`, `tests/`,
`scripts/` — the deliverable is the single `docs/` file and nothing else.
