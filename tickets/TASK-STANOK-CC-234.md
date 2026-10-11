# TASK-STANOK-CC-234: in-Pod live proof that the Bash tool and its tmp root work

impl: src/bash_smoke.py
test: tests/bash_smoke_test.py
docs: docs/bash_smoke.md

run.sh: exists

## Context

Incident cc231/cc233: under the Pod's read-only root filesystem the CLI Bash
tool's tmp root (`(CLAUDE_CODE_TMPDIR || "/tmp")/claude-<uid>`) was
unwritable — every Bash call died with ENOENT, the agent wrote blind, and the
host verdict was still PASS. The runtime was fixed host-side: both runner Pods
now mount a writable emptyDir at `/tmp` and set `CLAUDE_CODE_TMPDIR` to it.
Your task is a LIVE proof, from INSIDE the Pod, that the fix holds: the Bash
tool works and the tmp root is writable.

MANDATORY METHOD: early in your turn, BEFORE writing any file, use the Bash
tool at least three times: `pwd`, then `mkdir` + `ls` of a scratch dir under
`$TMPDIR`, then `python3 -c "print('bash-ok')"`. Delete the scratch dir when
done. The run is judged partly on your Bash usage — a run that never
succeeds at Bash is not accepted.

## Requirement

`src/bash_smoke.py` (stdlib only — `os`, `secrets`, `subprocess`):
- `tmp_root()` -> the directory the CLI Bash tool uses: the value of the
  environment variable `CLAUDE_CODE_TMPDIR` if set, otherwise `/tmp`.
- `probe()` -> a dict with at least these keys (facts about the current
  environment, computed, never hardcoded):
  - `"tmp_root"`: the resolved tmp root path;
  - `"tmp_root_writable"`: `True` if a uniquely-named file can be created
    and removed inside it (any `OSError` -> `False`);
  - `"claude_dir_ok"`: `True` if the directory `<tmp_root>/claude-<uid>`
    (uid from `os.getuid()`) can be CREATED (like the CLI Bash tool itself
    does — creation, not a pre-existing directory) and a uniquely-named file
    can be created and removed inside it; any `OSError` -> `False`. Do NOT
    require the directory to already exist: the fresh-check Pod runs no CLI
    session, so nothing creates it there — the invariant is that it CAN be
    created and written.
  - `"bash_runs"`: `True` if `subprocess.run(["bash", "-c", "pwd"])`
    exits 0, else `False`.

`tests/bash_smoke_test.py` (pytest, `def test_*`):
1. `test_tmp_root_resolution` (runs everywhere): with the environment
   monkeypatched — `CLAUDE_CODE_TMPDIR` set -> `tmp_root()` returns that
   value; unset -> `tmp_root() == "/tmp"`.
2. `test_probe_shape` (runs everywhere): `probe()` returns a dict containing
   all four keys with the right types; `tmp_root()` equals
   `probe()["tmp_root"]`.
3. `test_tmp_root_writable_in_pod` (Pod-only — skip unless the environment
   variable `STANOK_IN_POD` is set, same skipif pattern as
   `tests/pod_guard_test.py`): `probe()["tmp_root_writable"] is True` and
   `probe()["claude_dir_ok"] is True` — inside the Pod the tmp root must be
   writable and the CLI's `claude-<uid>` directory must be creatable and
   writable (the incident cc231/cc233 was exactly this creation failing).
4. `test_bash_runs_in_pod` (Pod-only, same pattern):
   `probe()["bash_runs"] is True` — a real `bash -c pwd` succeeds in the Pod.

## Acceptance criteria

- `scripts/run.sh test tests/bash_smoke_test.py` -> rc=0; `scripts/run.sh test --all` -> rc=0.
- Create NO files other than the three declared ones; scratch files only
  under `$TMPDIR`, deleted before you finish.
