# TASK-STANOK-CC-161: Loop-guard hook for BOTH supervisor TUI and machine (PreToolUse Bash, threshold 10, no whitelist)

Executor: operator/supervisor (infra config: root `.claude/` + `stanok/.claude/` — NOT a machine ticket, no launch).

## Background (verified 2026-09-25 against pinned cli.js 2.1.88)

- Settings/hooks load ONLY from `<originalCwd>/.claude/` — no parent fallback
  (`V_6("projectSettings"|"localSettings") = resolve(originalCwd)` in cli.js).
  Machine session cwd=`stanok/` → root `.claude/settings.local.json` is invisible
  to the machine. Safe to put a personal supervisor hook there.
- Hook input in 2.1.88 DOES carry `session_id` (schema: `session_id,
  transcript_path, cwd, permission_mode, agent_id, agent_type`).
- `jq 1.7` present at `/usr/bin/jq`.
- PreToolUse `exit 2` = deny, stderr is fed to the model as the reason.
- Root `.gitignore` does NOT currently ignore `/.claude/settings.local.json`
  (claim checked and refuted) — without the ignore line, `sync-skeleton`
  would push the personal hook into skeleton-pub.

## Requirements

1. Create `/home/hermes/darkcast/.claude/settings.local.json`:
   ```json
   {
     "hooks": {
       "PreToolUse": [
         {
           "matcher": "Bash",
           "hooks": [
             { "type": "command", "command": "$CLAUDE_PROJECT_DIR/.claude/hooks/loop-guard.sh" }
           ]
         }
       ]
     }
   }
   ```
2. Create `/home/hermes/darkcast/.claude/hooks/loop-guard.sh` (bash, `set -euo pipefail`):
   - Read hook JSON on stdin; extract `tool_input.command` and `session_id` via jq.
   - Empty command → exit 0.
   - **NO whitelist — every Bash command is counted, no exceptions.**
     Rationale: a looping agent repeats the same commands right up to
     completion, so read-only commands in a loop must be caught too; the
     whitelist only created bypass surface.
   - State file: `/tmp/claude-loop-guard/<session_id>.log` (mkdir -p).
   - Hash = sha256 of the exact command string; append one hash line per call.
   - **Count fix (bug in the original draft):** `grep -c` prints `0` AND exits 1
     on zero matches, so `|| echo 0` produced `COUNT="0\n0"` → arithmetic error
     → hook rc=1 noise on every first command. Use:
     ```bash
     COUNT=$(grep -c "^$HASH\$" "$STATE_FILE" 2>/dev/null || true)
     COUNT=${COUNT:-0}
     ```
   - **Threshold: block on the 10th literal repetition** — i.e. deny when
     `COUNT >= 9` (9 previous identical runs already seen). stderr message
     (Russian): «Эта команда уже выполнялась 10 раз в этой сессии без смены
     подхода. Не повторяй — действуй по уже полученному результату или явно
     смени подход.» exit 2.
   - Otherwise exit 0.
3. Add to root `/home/hermes/darkcast/.gitignore`:
   ```
   /.claude/settings.local.json
   ```

## Machine side (stanok/)

Key fact (verified in cli.js 2.1.88, function `Mb4`): hooks are loaded ONLY
from `userSettings` / `projectSettings` / `localSettings` — **NOT from
`flagSettings`**. Therefore the machine hook must NOT go into
`settings.stanok.json` (loaded via `settings=`); it goes into
`stanok/.claude/settings.json` (projectSettings, machine cwd=`stanok/`).

4. Add a `hooks` section to `/home/hermes/darkcast/stanok/.claude/settings.json`
   (currently `{}`):
   ```json
   {
     "hooks": {
       "PreToolUse": [
         {
           "matcher": "Bash",
           "hooks": [
             { "type": "command", "command": "$CLAUDE_PROJECT_DIR/.claude/hooks/loop-guard.sh" }
           ]
         }
       ]
     }
   }
   ```
5. Create `/home/hermes/darkcast/stanok/.claude/hooks/loop-guard.sh` — same
   logic as the supervisor script (item 2): jq parse, NO whitelist (count
   everything), sha256 count with the `|| true` / `${COUNT:-0}` fix, deny on
   10th literal repetition (`COUNT >= 9`), state
   `/tmp/claude-loop-guard/<session_id>.log`.
   (Deliberate copy, not a shared file: the container must be self-contained.)
6. Tamper-safety (already in place, verify only): the machine cannot modify
   its own hook — `settings.stanok.json` denies `Edit(.claude/**)` and the
   sandbox `denyWrite`/`denyRead` covers `../.claude`; the hook process is
   spawned by the CLI, outside the machine's sandboxed Bash.

§7 citation: native PreToolUse hook primitive (no launcher mechanism added);
incident class = command loops observed in the supervisor TUI 2026-09-25 and
the SMOKE-02-class stuck-run risk on the machine.

## Acceptance criteria

- First 9 runs of any Bash command (identical or not): hook exits 0, no error
  text to the model.
- 10th literal repetition of ANY command (mutating or read-only) in one
  session: exit 2, model receives the stderr message, tool call denied;
  11th, 12th… also denied.
- No whitelist: read-only commands are counted and blockable like any other.
- `git status --porcelain` in the root repo shows no `.claude/settings.local.json`
  (ignored); `sync-skeleton --diff` does not list it.
- Machine session: hook IS active — in a machine run, the 10th literal
  repetition of a Bash command is denied with the stderr message (visible in
  the Opik trace / run output).
- `settings.stanok.json` is unchanged (hooks there would be silently ignored).

## Non-goals

- No PostToolUse audit variant yet (optional follow-up).
- No state cleanup/cron (unbounded `/tmp` growth accepted).
- No changes to `stanok/` launcher code (only `stanok/.claude/` config + hook script).
