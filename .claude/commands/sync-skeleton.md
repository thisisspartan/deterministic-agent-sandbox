---
description: Interactively sync this repo's infrastructure into skeleton-pub (diff preview + push option)
---

Sync **this repo** (SRC = current working directory, path-agnostic) into **skeleton-pub**
(DST = `/home/hermes/skeleton-pub`, always the destination). Only infrastructure is
synced; machine-generated code (`stanok/src|tests|docs`) and project history (tickets,
review docs, evidence) are excluded. Clean templates stay clean.

## 1. Determine the repos
- SRC = `git rev-parse --show-toplevel` (the repo you are in — do NOT hardcode a path).
- DST = `/home/hermes/skeleton-pub` (fixed).
- The sync engine is `"$SRC/.claude/sync-skeleton.sh"`.

## 2. Preview the diff (do NOT apply yet)
Set the vars as SEPARATE statements first, THEN run. A `VAR=... cmd "$VAR/..."`
one-liner is WRONG: the shell expands `$SRC` before the prefix assignment takes
effect, so `"$SRC/.claude/sync-skeleton.sh"` becomes `/.claude/sync-skeleton.sh`
→ exit 127.
    SRC="$(git rev-parse --show-toplevel)"
    DST="/home/hermes/skeleton-pub"
    "$SRC/.claude/sync-skeleton.sh" --diff
It prints, per category, the files to ADD / MODIFY / REMOVE (submodule infra + top-level
infra) and a `TOTAL changes:` count. **Show the user this list.**
- If `TOTAL changes: 0` → tell the user "already in sync, nothing to do" and stop.

## 3. Ask how to proceed (AskUserQuestion)
"Both repos" = the two DST repos: skeleton-pub (top) and its submodule.
SRC (this repo) is READ-ONLY for the sync — never committed, never pushed.
- (a) **Full sync** — apply + commit skeleton-pub (top + submodule) + push both to GitHub.
- (b) **Local only** — apply + commit skeleton-pub (top + submodule), NO push.
Do not apply until the user chooses.

## 4. Apply
Re-use the `SRC`/`DST` vars from step 2 (do NOT inline-assign them on the same
line as the command — see the pitfall note in step 2).
- (a): `"$SRC/.claude/sync-skeleton.sh"`
- (b): `"$SRC/.claude/sync-skeleton.sh" --no-push`

Report the final status: the submodule + top-level commit SHAs and the push result
(or "local only"). Do not read logs or poll.
