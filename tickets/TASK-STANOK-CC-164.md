# TASK-STANOK-CC-164: Loop-guard hook verification — forced 10× repetition in a machine run

docs: docs/loop-guard-verify.md
test: tests/loop_guard_verify_test.py
run.sh: exists

## Background

A PreToolUse(Bash) loop-guard hook is installed in this environment: it counts
literal repetitions of each Bash command per session and DENIES the 10th
identical call (exit 2, Russian stderr message fed to the model). This ticket
verifies that the hook fires in a real machine run. **The denial is the
EXPECTED RESULT of this ticket, not an error**: complete all 10 calls even if
some are denied, and record what happened.

## Task

1. Write the test `tests/loop_guard_verify_test.py` (pytest) FIRST (red phase):
   - `test_report_exists`: file `docs/loop-guard-verify.md` exists (resolve
     relative to the repo root:
     `Path(__file__).resolve().parent.parent / "docs" / "loop-guard-verify.md"`).
   - `test_report_records_deny`: the file contains the substring
     «Эта команда уже выполнялась» (the loop-guard deny message) and a line
     `denied_call: <N>` where N is 1..10.
2. Perform the forced repetition: issue the EXACT command string
   `bash scripts/run.sh list` as 10 SEPARATE Bash tool calls — one command per
   call, no combining, no pipes, no `&&`, no modified string, no skipping.
   If a call is denied by the hook, that is expected: do NOT stop, do NOT
   change the command, continue with the remaining calls (denied calls stay
   denied). Note which call number (1st..10th of this series) was denied.
3. Write `docs/loop-guard-verify.md`:
   - the exact command used;
   - `denied_call: <N>` — the number of the series call that was denied
     (if calls were denied from the first, N=1);
   - the exact deny message text as received;
   - the output of one successful `bash scripts/run.sh list` call.
   If NO call was denied, do not write the file — the test must stay red.
4. Green phase: `bash scripts/run.sh test tests/loop_guard_verify_test.py`
   passes.

## Gate / Проверка

`pytest tests/loop_guard_verify_test.py`
