# TASK-STANOK-CC-055 — skeleton-pub history sanitization (orphan rewrite)

Status: `[x] DONE` (executed by the supervisor on the host — public-repo hygiene, not project code)

## Task

The public repos (`deterministic-agent-sandbox` root +
`deterministic-agent-sandbox-stanok` submodule) contained removed project
artifacts in their git history (project modules tetris/fire/fire3d/rng/slug,
tickets 008–048, Russian docs/specs — commits `96aedb5` / `9b432c0`).
Current trees were already sanitized; the history was not.

## Action

Orphan-branch rewrite of BOTH public repos: a single new root commit from the
current (sanitized) tree, force-push to `origin/main`. History wiped.
Scope: skeleton-pub + its stanok submodule ONLY — `darkcast` untouched.

## Result

- stanok: new root commit, tree identical to pre-rewrite `7493dab`
  (= darkcast `4cf8546` tree: CC-053 infra, no roman/test files).
- root: new root commit, tree identical to pre-rewrite `b2187f4`
  (generic templates, empty tickets/, submodule pointer -> new stanok SHA).
- Verified: single-commit history, clean trees, content unchanged.
