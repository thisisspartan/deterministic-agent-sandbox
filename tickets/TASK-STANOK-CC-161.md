# TASK-STANOK-CC-161: Loop-guard hook for BOTH supervisor TUI and machine (PreToolUse Bash, threshold 10, no whitelist)

Executor: operator/supervisor (infra config: root `.claude/` + `stanok/.claude/` — NOT a machine ticket, no launch).

## Background (verified 2026-09-25 against pinned cli.js 2.1.88)

- Settings/hooks load ONLY from `<originalCwd>/.claude/` — no parent fallback
  (`V_6("projectSettings"|"localSettings") = resolve(originalCwd)` in cli.js).
  Machine session cwd=`stanok/` → root `.claude/settings.local.json` is invisible
  to the machine. Safe to put a personal supervisor hook there.
- Hook input in 2.1.88 DOES carry `session_id` (schema: `session_id,
  transcript_path, cwd, permission_mode, agent_id, agent_type`).
- `python3` is available in BOTH environments (supervisor host and the
  machine Docker image — py stack). No `jq` dependency: the hook is a single
  python3 process (~20 ms spawn, sha256 itself is 0.47 µs — measured),
  vs 6 process spawns in the bash draft.
- PreToolUse `exit 2` = deny, stderr is fed to the model as the reason.
- Hook latency budget: ~30–50 ms per Bash call → <1% overhead on a run;
  zero LLM/KV impact (local process, no inference requests).
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
             { "type": "command", "command": "$CLAUDE_PROJECT_DIR/.claude/hooks/loop-guard.py" }
           ]
         }
       ]
     }
   }
   ```
2. Create `/home/hermes/darkcast/.claude/hooks/loop-guard.py` (python3,
   `chmod +x`, shebang `#!/usr/bin/env python3`):
   - Read hook JSON on stdin; extract `tool_input.command` and `session_id`
     with the `json` module. **Fail-open: ANY exception (bad JSON, missing
     keys, IO error) → `exit 0`** — the hook must never block or hang a turn.
   - Empty command → exit 0.
   - **NO whitelist — every Bash command is counted, no exceptions.**
     Rationale: a looping agent repeats the same commands right up to
     completion, so read-only commands in a loop must be caught too; the
     whitelist only created bypass surface.
   - State file: `/tmp/claude-loop-guard/<session_id>.log` (makedirs).
   - Hash = sha256 of the exact command string (0.47 µs — not a bottleneck;
     the process spawn is ~44 000× more expensive, measured).
   - Count = number of previous lines equal to the hash (file read, no grep
     process).
   - **Threshold: block on the 10th literal repetition** — i.e. deny when
     `COUNT >= 9` (9 previous identical runs already seen). stderr message
     (Russian): «Эта команда уже выполнялась 10 раз в этой сессии без смены
     подхода. Не повторяй — действуй по уже полученному результату или явно
     смени подход.» exit 2. On deny do NOT append (stays blocked on 11th,
     12th…).
   - Otherwise append the hash line and exit 0.
3. Add to root `/home/hermes/darkcast/.gitignore`:
   ```
   /.claude/settings.local.json
   ```

Reference implementation (both copies, `chmod +x`):

```python
#!/usr/bin/env python3
"""PreToolUse(Bash) loop guard. exit 2 = deny, stderr идёт модели как причина.
Fail-open: любой сбой = exit 0 (хук никогда не блокирует и не вешает turn)."""
import sys, json, hashlib, os

try:
    d = json.load(sys.stdin)
    cmd = (d.get("tool_input") or {}).get("command") or ""
    sid = d.get("session_id") or "nosession"
except Exception:
    sys.exit(0)
if not cmd:
    sys.exit(0)

h = hashlib.sha256(cmd.encode()).hexdigest()
p = f"/tmp/claude-loop-guard/{sid}.log"
os.makedirs(os.path.dirname(p), exist_ok=True)
try:
    with open(p) as f:
        n = sum(1 for line in f if line.strip() == h)
except (FileNotFoundError, OSError):
    n = 0

# Порог 10: deny на 10-м буквальном повторе (9 предыдущих уже были).
if n >= 9:
    sys.stderr.write(
        f"Эта команда уже выполнялась {n + 1} раз в этой сессии без смены "
        "подхода. Не повторяй — действуй по уже полученному результату или "
        "явно смени подход.\n")
    sys.exit(2)

with open(p, "a") as f:
    f.write(h + "\n")
sys.exit(0)
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
             { "type": "command", "command": "$CLAUDE_PROJECT_DIR/.claude/hooks/loop-guard.py" }
           ]
         }
       ]
     }
   }
   ```
5. Create `/home/hermes/darkcast/stanok/.claude/hooks/loop-guard.py` — same
   logic as the supervisor script (item 2): json parse, fail-open, NO
   whitelist (count everything), sha256 count, deny on 10th literal
   repetition (`COUNT >= 9`), state `/tmp/claude-loop-guard/<session_id>.log`.
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
