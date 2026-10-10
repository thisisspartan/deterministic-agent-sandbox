# TASK-STANOK-CC-231: in-Pod proof that the runtime switch never reaches the Pod

test: tests/runtime_env_test.py

run.sh: exists

## Context

The host runtime default has just been cut over (you cannot see it — it is
outside your zones): launches now DEFAULT to the k8s orchestrator; the
deprecated Docker path runs only on an explicit STANOK_RUNTIME=docker. The
runtime flag is a HOST-only concern: the worker Pod's environment is an
explicit whitelist (label/nonce/server/opik/model/commit/log-dir/pod-repo)
and never carries STANOK_RUNTIME. Your test proves from INSIDE the Pod that
the flag is invisible — neither to the Python process nor to a child Bash.
The task payload is deliberately small; its purpose is the proof.

## Requirement

`tests/runtime_env_test.py` (pytest, `def test_*`), reusing the EXISTING
module `src/env_probe.py` (`from src.env_probe import bash_print`) — do NOT
modify `src/`:

1. `test_runtime_flag_not_in_python`: `os.environ.get("STANOK_RUNTIME")`
   MUST be `None`.
2. `test_runtime_flag_not_in_bash`: `bash_print("${STANOK_RUNTIME-unset}")`
   MUST be `"unset"`.

Note: `src/env_probe.py` already exists and works — these tests document a
NEW invariant and are expected to pass on first run (no red phase).

## Acceptance criteria

- `scripts/run.sh test tests/runtime_env_test.py` -> rc=0;
  `scripts/run.sh test --all` -> rc=0.
- Create NO files other than the one declared test file; modify NOTHING else.

## Expected pipeline outcome (host-side, checked by the supervisor — not by you)

Launch WITHOUT STANOK_RUNTIME (the new default) -> k8s dispatch -> payload
accepted (nonce match) -> contract clean -> fresh Job green -> final verdict
PASS, rc=0; `opik_traces` > 0.
