# TASK-STANOK-CC-067 — Portable native-sandbox config (item 1/3)

## Problem
`stanok/.claude/settings.stanok.json` hardcodes `/home/hermes/darkcast/stanok/...`
in `sandbox.filesystem.denyWrite`. Proof it is per-clone hand-edited: the only diff
between this tree and the `~/skeleton-pub` clone is those three path lines. On any
other clone the paths silently stop matching, so the native deny does nothing.

## Change
Replace the three absolute paths with `./`-relative paths:
`./.git`, `./hooks`, `./.claude/settings.stanok.json`.

Verified in cli.js: on Linux every `filesystem` path is passed through `oV()`, which
expands `~`, `./`, `../` and bare relatives against `process.cwd()`. The launcher runs
with `cwd=REPO_ROOT` and the inner bwrap inherits it, so these resolve to the repo.

## Scope honesty (do NOT read this as closing the audit finding)
This fixes **portability** only. It does **not** add an `allowWrite` scope over
`src/tests/docs/evidence`. Native `filesystem` allow-lists are additive and deny is
subtractive, so the "read-only repo + writable carve-outs" invariant is still enforced
exclusively by `sandbox-run.sh` (IRON STOP: kept). The audit's correctness finding
remains open for a future, riskier cycle.

## Files
- `stanok/.claude/settings.stanok.json`

## Smoke
One shared light ticket `tickets/TASK-STANOK-SMOKE-01.md` (creates `tests/smoke.test.js`
+ `src/smoke.js`) run through `launch.sh`; expects rc=0 / verifier=PASS. Must be run on a
clean submodule (dirty-tree gate rc=22 otherwise) — hence commit this first.

## Acceptance
- JSON valid; `denyWrite` resolves to the repo under any clone location.
- Smoke run rc=0 / verifier=PASS.
