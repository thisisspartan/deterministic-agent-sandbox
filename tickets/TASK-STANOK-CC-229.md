# TASK-STANOK-CC-229: k8s smoke under readOnlyRootFilesystem — in-Pod proof (SPEC-READONLY-ROOT acceptance)

impl: src/ro_root_smoke.py
test: tests/ro_root_smoke_test.py

run.sh: exists

## Context

ACCEPTANCE ticket for the new Pod hardening (host-side change,
`specs/SPEC-READONLY-ROOT-2026-10-10.md`): the worker and fresh Pods now run
with `readOnlyRootFilesystem: true`. All legitimate Pod writes already go to
the `/stanok-work` emptyDir (the runner re-redirects HOME/TMPDIR there). Your
test proves from INSIDE the Pod that the hardening is in effect AND the
designated writable paths still work — i.e. the read-only root did not break
the runtime. The task payload itself is deliberately trivial: its purpose is
to exercise the full pipeline under the new securityContext.

## Requirement

`src/ro_root_smoke.py`:
- `mul(a, b)` -> `a * b`.
- `write_probe(path)` -> `True` if a uniquely-named file can be created and
  removed inside `path`, `False` if the attempt raises `OSError`
  (EROFS/EPERM). stdlib only (`os`, `tempfile` or a fixed name).

`tests/ro_root_smoke_test.py` (pytest, `def test_*`):
1. `mul` basics: positive, zero identity `mul(0, x) == 0`, commutativity.
2. `test_root_is_read_only`: `write_probe("/")` MUST be `False` — creating a
   file at the filesystem root must fail. If it succeeds, the hardening is
   NOT in effect and the test fails.
3. `test_work_dir_writable`: `write_probe("/stanok-work")` MUST be `True`
   (the emptyDir is the designated writable zone in both Pods). Probe
   `TMPDIR`/`HOME` from the environment ONLY when the value starts with
   `/stanok-work` — the runner's redirect — such a probe MUST be `True`.
   When the variable is absent OR points elsewhere (e.g. the image default
   `/home/stanok` in the fresh Pod, which has no runner redirect and is
   legitimately read-only), SKIP that probe — do not assert on it.

## Acceptance criteria

- `scripts/run.sh test tests/ro_root_smoke_test.py` -> rc=0; `scripts/run.sh test --all` -> rc=0.
- Create NO files other than the two declared ones.

## Expected pipeline outcome (host-side, checked by the supervisor — not by you)

Payload accepted (nonce match) → evidence + changes.patch → contract clean →
fresh Job green (tests 2/3 pass there too: the fresh Pod has the same
read-only root and the same emptyDir) → final verdict PASS, rc=0, patch
applied; `opik_traces` > 0; no EROFS entries in errors/failures.
