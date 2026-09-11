# TASK-STANOK-CC-068 — Single source of truth for machine env (item 2/3)

## Problem
The machine process received the same env keys from two places:
`stanok/.claude/settings.stanok.json` → `env` and
`launcher/stanok.py::build_agent_env()` (passed as SDK `env=`). The copies had
already drifted (proxies / `MAX_THINKING_TOKENS` / `DISABLE_ADAPTIVE_THINKING`
only in Python; `MAX_CONCURRENT_SUBAGENTS`-style keys only in `P0-launch.sh`).

## Root cause (verified in cli.js `jUK()`)
At CLI startup:
`Object.assign(process.env, settings.env)` — i.e. **settings.env is applied AFTER
the SDK has set the process environment and therefore OVERRIDES it**. So a key
present in both does not "merge": settings silently wins and the runtime value in
`build_agent_env()` is dead.

Concrete dead knobs before this change:
- `API_TIMEOUT_MS` hardcoded `600000` in settings → `STANOK_API_TIMEOUT_S` ignored.
- `ANTHROPIC_DEFAULT_*_MODEL` / `CLAUDE_CODE_SUBAGENT_MODEL` hardcoded in settings →
  `STANOK_MODEL` ignored.
Both were invisible only because the defaults happen to match.

## Change
Canonical split:
- **Static, host-independent** → `settings.stanok.json.env`:
  `ANTHROPIC_AUTH_TOKEN`, `ANTHROPIC_API_KEY`, all `CLAUDE_CODE_DISABLE_*`,
  retry/output/compaction limits, plus the static flags moved in from Python:
  `MAX_THINKING_TOKENS`, `CLAUDE_CODE_DISABLE_ADAPTIVE_THINKING`,
  `DISABLE_AUTOUPDATER`, `DISABLE_NON_ESSENTIAL_MODEL_CALLS`,
  `CLAUDE_CODE_DISABLE_ADVISOR_TOOL`.
- **Derived from runtime env** → `build_agent_env()` only (and REMOVED from settings
  so settings cannot override them): `PATH`, `ANTHROPIC_BASE_URL`,
  `ANTHROPIC_MODEL`, `ANTHROPIC_DEFAULT_{SONNET,OPUS,HAIKU}_MODEL`,
  `CLAUDE_CODE_SUBAGENT_MODEL`, `API_TIMEOUT_MS`, `http_proxy`/`https_proxy`/
  `all_proxy`/`no_proxy`.

Key intersection between the two sources is now **empty** by construction
(checked: 20 static + 12 runtime, no overlap, no key dropped).

## Not touched
`P0-launch.sh` exports are the **supervisor** session's env source. That session
does not load `settings.stanok.json` (cwd is the root repo), so collapsing it into
settings would break it. The audit's "three copies of one" conflates two different
processes. Only the machine's two sources are unified here.

## Behavior under current defaults
Neutral: every value that moved is identical to what it shadowed. The change only
makes `STANOK_MODEL` / `STANOK_API_TIMEOUT_S` actually take effect.

## Files
- `stanok/.claude/settings.stanok.json`
- `stanok/launcher/stanok.py`

## Smoke
`tickets/TASK-STANOK-SMOKE-01.md` through `launch.sh` (clean submodule): proves the
API path still works with model/auth/base-url now coming from the runtime dict.

## Acceptance
- Valid JSON + `py_compile`.
- Env key intersection empty.
- Smoke rc=0 / verifier=PASS.
