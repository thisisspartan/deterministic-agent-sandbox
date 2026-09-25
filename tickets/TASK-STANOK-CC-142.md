# TASK-STANOK-CC-142 — drop the committed cli.js full-bundle backups

Supervisor-executed in the **CLI repo** (`~/git/claude-code-2.1.88`), branch
`base`. No machine launch (not `stanok/` TDD work). Part of
`specs/PLAN-cli-js-hygiene-2026-09-25.md` (F1).

## Incident / context

Two whole copies of the 13 MB minified bundle are committed on the shipped line:

- `cli.js.bak-preM-20260917` — 13 050 416 B
- `cli.js.bak-preTemp-20260924` — 13 050 253 B

~26 MB in a `.git` that already measures 362 MB. The repo has **no `.gitignore`**.
They are ad-hoc "before I edit" snapshots; git history already stores every prior
blob, so they add nothing recoverable.

## Change (scope: working tree only)

- `git rm cli.js.bak-preM-20260917 cli.js.bak-preTemp-20260924` on `base`.
- Add a minimal `.gitignore` that keeps such snapshots local (`cli.js.bak*`).
- Keep a local (untracked) copy if the operator wants one.

## Verification

- `git rev-parse base:cli.js` **before and after** the commit is identical
  (`809caeef…`) — the shipped blob must not move.
- `git status` clean; `git log --oneline -1` shows the removal.
- `grep -c 'bak-pre' .gitignore` / `git ls-files | grep bak-pre` → empty.

## Non-goals / residuals

- **No history rewrite.** Purging the 26 MB from history is `git filter-repo`
  (destructive, rewrites every downstream sha) — it is CC-145's decision, not
  this ticket.
- `setup.sh:42 CLI_JS_SHA` is untouched (it hashes `cli.js`, not the backups).
