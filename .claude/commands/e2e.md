---
description: E2E pipeline test — launch the machine on a ticket, block until done, verify the verdict
---

Run the end-to-end pipeline test on a ticket: launch the machine, block until the run
finishes, verify `stanok/evidence/<label>/summary.json` (rc=0 + verifier=PASS → E2E-OK).

Arguments: `$ARGUMENTS` = `<ticket.md> <label>`. If either is missing, ask the user.

## 1. Pre-flight
- ROOT = `git rev-parse --show-toplevel` (do NOT hardcode a path).
- `git -C "$ROOT/stanok" status --porcelain` — if dirty, commit first
  (`git -C "$ROOT/stanok" add -A && git -C "$ROOT/stanok" commit --no-verify -m "chore: save state before e2e"`);
  enforcement lives in one place — launch.sh's dirty-tree gate (rc=22).

## 2. Run (ONE command — no polling, no log reads while the machine runs)
From ROOT, run with the Bash tool (`run_in_background: true`):
    ./.claude/e2e.sh <ticket.md> <label>
It launches the machine (`--background`), blocks in a `while ... status ... running` loop,
and prints the final verdict. Wait for the completion notification.
Do NOT poll `launch.sh status`, do NOT read `.launch.log` / evidence files while it runs.

## 3. Read the result ONCE
Read the background task's output file. The last lines are:
    E2E-OK: rc=0 verifier=PASS probe=...
or
    E2E-FAIL: rc=<n> verifier=<...>
    (+ errors/failures lines from summary.json)

- **E2E-OK** → report OK (rc, verifier, probe).
- **E2E-FAIL** → report rc/verifier + the errors/failures lines. If more detail is needed,
  read `stanok/evidence/<label>/summary.json` exactly ONCE.
- If e2e.sh was interrupted but the machine still runs
  (`./stanok/launch.sh status <label>` → `"state": "running"`), re-attach with the blocking wait:
      while ./stanok/launch.sh status <label> | grep -q '"state": "running"'; do sleep 15; done && ./stanok/launch.sh status <label>
  then read summary.json once.
