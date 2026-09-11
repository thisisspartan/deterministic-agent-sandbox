# TASK-STANOK-CC-075 — Machine Bash dead: flagSettings-relative denyWrite base

Supervisor-executed (NOT a machine task). Regression introduced by CC-067.

## Finding (verified, source-level)

Since CC-067 (`df06d93`, 2026-09-11 10:21, "portable sandbox config") the machine's
Bash tool is **completely dead**. Every allowed `bash scripts/run.sh …` call returns:

```
Exit code 1
bwrap: Can't create file at /home/hermes/darkcast/stanok/.claude/.git: Read-only file system
```

Raw SDK stream evidence (host-side, escapes the tmpfs HOME):
`/tmp/stanok-logs/smoke-portable-sandbox/session-ad7d1004.jsonl:16,37,41` — and the
same error in every run from CC-067's own verification smoke through CC-074.

### Root cause (claude-code 2.1.88, source-verified)

`.claude/settings.stanok.json` had:

```json
"sandbox": { "filesystem": { "denyWrite": ["./.git", "./hooks", "./.claude/settings.stanok.json"] } }
```

The SDK passes the settings **file path** as `--settings` (no SDK `sandbox` option), so
cli.js classifies it as `flagSettings`. Sandbox filesystem paths are resolved by:

- `resolveSandboxFilesystemPath(p, source) = expandPath(p, getSettingsRootPathForSource(source))`
  (`source/src/utils/sandbox/sandbox-adapter.ts:138-146`)
- `getSettingsRootPathForSource('flagSettings') = dirname(resolve(getFlagSettingsPath()))`
  (`source/src/utils/settings/settings.ts:248-251`) → **`<repo>/.claude`**
- `expandPath(p, base)` resolves a relative `p` against `base`
  (`source/src/utils/path.ts:32`)

So every `./`-relative denyWrite is rebased into `.claude/`:

| written              | resolves to                                    |
|----------------------|------------------------------------------------|
| `./.git`             | `<repo>/.claude/.git`            (nonexistent) |
| `./hooks`            | `<repo>/.claude/hooks`           (nonexistent) |
| `./.claude/settings.stanok.json` | `<repo>/.claude/.claude/settings.stanok.json` (nonexistent) |

For a `denyWrite` path that does **not** exist, the native runtime must CREATE the bwrap
mountpoint; `sandbox-run.sh` pre-creates `<repo>/.git` but not these rebased paths, and
the repo is `--ro-bind` → `Read-only file system`.

CC-067's premise — "`oV()` expands against cwd=REPO_ROOT" — holds for the *permissions-rule*
resolver `oV()`, but `sandbox.filesystem.*` uses the **flagSettings-keyed** resolver above.
Before CC-067 the paths were absolute, so Bash worked.

### Why it was masked

`verifier: PASS` comes from the host-side PostToolUse hook (`hooks/verifier.sh`), which the
inner sandbox does **not** wrap. A run therefore "PASSes" even with Bash dead. All
CC-067/068/069/070 and CC-072/073/074 "verifications" never exercised the machine's own Bash.

## Change

Rebase the three denyWrite entries against `.claude` so they land on the intended
`<repo>` paths, keeping the config portable (no absolute host path):

```json
"denyWrite": ["../.git", "../hooks", "./settings.stanok.json"]
```

- `../.git` → `<repo>/.git`  (already pre-created by sandbox-run.sh)
- `../hooks` → `<repo>/hooks`
- `./settings.stanok.json` → `<repo>/.claude/settings.stanok.json`

## Acceptance

- JSON parses.
- `hooks/doctor.sh` on a clean tree: all ok.
- Verification smoke: the session stream (host `session-<run_id>.jsonl`) shows **no**
  `bwrap: Can't create file`; at least one `bash scripts/run.sh …` call returns rc=0.

Verified 2026-09-11 (`smoke-cc075`, `TASK-STANOK-SMOKE-01.md`): doctor **13 ok / 0 fail**;
smoke rc=0, verifier=PASS, CLEAN-FIRST, 1 turn 85s, live window 16104; session stream
`/tmp/stanok-logs/smoke-cc075/session-ceaed0cb.jsonl` = **0** `Can't create file` hits and
`bash scripts/run.sh list`, `… test tests/smoke.test.js`, `… smoke src/smoke.js` all
returned non-error (rc=0).

## Explicit non-change

- `sandbox-run.sh` is **untouched** (IRON STOP; the mount-preflight was dropped in CC-070).
- `denyRead` uses `~`-paths, which `expandPath` resolves source-independently — no change.
