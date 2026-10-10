# TASK-STANOK-CC-230: in-Pod proof of nonce isolation and fresh-Pod HOME/TMPDIR alignment

impl: src/env_probe.py
test: tests/env_probe_test.py

run.sh: exists

## Context

Two host-side fixes just landed (you cannot see them — they are outside your
zones): (1) the in-Pod runner now consumes `STANOK_NONCE` via
`os.environ.pop` and drops it from the session env, so the agent's Bash must
no longer inherit it; (2) the fresh-check Pod now sets `HOME=/stanok-work/home`
and `TMPDIR=/stanok-work/tmp` (the read-only root from CC-229 makes the image
default `/home/stanok` unwritable — tests writing to `~/.cache` need a
writable HOME in the emptyDir). Your tests prove from INSIDE the Pod that
both hold. The task payload is deliberately small; its purpose is the proof.

## Requirement

`src/env_probe.py` (stdlib only — `os`, `subprocess`, `errno`, `secrets`):
- `bash_print(expr)` -> the stripped stdout of `bash -c 'echo "<expr>"'`.
- `write_error(path)` -> `None` if a uniquely-named file can be created and
  removed inside `path`; otherwise the `errno` (int) of the raised `OSError`.

`tests/env_probe_test.py` (pytest, `def test_*`):
1. `test_bash_print_sanity`: `bash_print("hello") == "hello"`.
2. `test_nonce_not_inherited`: `bash_print("${STANOK_NONCE-unset}")` MUST be
   `"unset"` — the payload nonce must not be visible to any child Bash.
3. `test_root_write_denied_erofs`: `write_error("/stanok-ro-test")` MUST
   equal `errno.EROFS` — writing outside the emptyDir must fail with
   Read-only file system.
4. `test_home_tmpdir_aligned_writable`: `HOME` and `TMPDIR` from the
   environment MUST be set, MUST start with `/stanok-work`, and
   `write_error(...)` on each MUST be `None` (the designated writable zone).

## Acceptance criteria

- `scripts/run.sh test tests/env_probe_test.py` -> rc=0; `scripts/run.sh test --all` -> rc=0.
- Create NO files other than the two declared ones.

## Expected pipeline outcome (host-side, checked by the supervisor — not by you)

Payload accepted (nonce match) → contract clean → fresh Job green (tests 2-4
pass there too: the fresh Pod has the aligned HOME/TMPDIR and the same
read-only root) → final verdict PASS, rc=0; `opik_traces` > 0; no EROFS
entries in errors/failures.

## Addendum (host-side, operator spec 2026-10-10 — NO machine deliverables)

Item 3 of the operator's scope was implemented host-side after the machine
run: `job_deadline()` (launcher/k8s.py) renders `activeDeadlineSeconds`
with default 1800 s (30-min insurance; `STANOK_K8S_JOB_DEADLINE_S`
overrides) and `ttlSecondsAfterFinished: 300` in BOTH Job templates.
Pinned by `test_k8s_manifests.py` (timeouts + deadline default/override).
