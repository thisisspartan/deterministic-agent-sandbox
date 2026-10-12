# TASK-STANOK-VERIFY-REGISTRY (smoke): one-page note on the registry image-delivery contract

docs: docs/verify-registry.md

run.sh: exists

## Context

This is a SMOKE ticket: its purpose is to exercise the launch pipeline end-to-end
after the image-delivery switch to the node-local registry. It adds NO code and
NO tests. The only deliverable is one short documentation file.

## Requirement

`docs/verify-registry.md` — at most 40 lines, plain markdown, describing the
image-delivery contract as it works today:

- the machine image `stanok-machine` is built and pushed by `setup.sh` to the
  node-local registry `192.168.122.156:5000`;
- the Job Pod references the image by DIGEST (`192.168.122.156:5000/stanok-machine@sha256:…`),
  resolved from `docker inspect .RepoDigests` — never by a mutable tag;
- a launch preflight refuses to start a run when the image is absent locally or
  not pushed (rc=16, the fix is named);
- kubelet re-pulls the exact image by digest after any image GC.

Do not invent facts beyond the four points above. Do not touch `src/`, `tests/`,
`scripts/` — the deliverable is the single `docs/` file and nothing else.
