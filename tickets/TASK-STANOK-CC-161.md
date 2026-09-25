# TASK-STANOK-CC-161: Supervisor loop-guard hook (PreToolUse Bash, threshold 5)

Executor: operator/supervisor (supervisor-zone infra: root `.claude/` — NOT a machine ticket, no launch).

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
   - **Read-only whitelist (skip counting AND never block):** commands whose
     first token/segment is one of: `git status`, `git log`, `git diff`,
     `git show`, `git rev-parse`, `ls`, `cat`, `wc`, `grep`, `rg`, `head`,
     `tail`, `which`, `jq` (read-only invocations). Match on the command
     prefix before any pipe/redirect.
   - State file: `/tmp/claude-loop-guard/<session_id>.log` (mkdir -p).
   - Hash = sha256 of the exact command string; append one hash line per call.
   - **Count fix (bug in the original draft):** `grep -c` prints `0` AND exits 1
     on zero matches, so `|| echo 0` produced `COUNT="0\n0"` → arithmetic error
     → hook rc=1 noise on every first command. Use:
     ```bash
     COUNT=$(grep -c "^$HASH\$" "$STATE_FILE" 2>/dev/null || true)
     COUNT=${COUNT:-0}
     ```
   - **Threshold: block on the 5th literal repetition** — i.e. deny when
     `COUNT >= 4` (4 previous identical runs already seen). stderr message
     (Russian): «Эта команда уже выполнялась 5 раз в этой сессии без смены
     подхода. Не повторяй — действуй по уже полученному результату или явно
     смени подход.» exit 2.
   - Otherwise exit 0.
3. Add to root `/home/hermes/darkcast/.gitignore`:
   ```
   /.claude/settings.local.json
   ```

## Acceptance criteria

- First run of any Bash command: hook exits 0, no error text to the model.
- 5th literal repetition of a mutating command in one session: exit 2, model
  receives the stderr message, tool call denied.
- Read-only whitelisted commands: never counted, never blocked, any number of
  repetitions.
- `git status --porcelain` in the root repo shows no `.claude/settings.local.json`
  (ignored); `sync-skeleton --diff` does not list it.
- Machine session (cwd=`stanok/`) is unaffected — hook file is never loaded there.

## Non-goals

- No PostToolUse audit variant yet (optional follow-up).
- No state cleanup/cron (unbounded `/tmp` growth accepted).
- No changes to `stanok/` launcher or machine settings.
