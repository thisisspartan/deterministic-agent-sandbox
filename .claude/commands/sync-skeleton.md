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
Run:
    SRC="<src>" DST=/home/hermes/skeleton-pub "$SRC/.claude/sync-skeleton.sh" --diff
It prints, per category, the files to ADD / MODIFY / REMOVE (submodule infra + top-level
infra) and a `TOTAL changes:` count. **Show the user this list.**
- If `TOTAL changes: 0` → tell the user "already in sync, nothing to do" and stop.

## 3. Ask how to proceed (AskUserQuestion)
- (a) **Full sync** — apply + commit both repos + push both to their GitHub remotes.
- (b) **Local only** — apply + commit both repos, NO push.
Do not apply until the user chooses.

## 4. Apply
- (a): `SRC="<src>" DST=/home/hermes/skeleton-pub "$SRC/.claude/sync-skeleton.sh"`
- (b): `SRC="<src>" DST=/home/hermes/skeleton-pub "$SRC/.claude/sync-skeleton.sh" --no-push`

Report the final status: the submodule + top-level commit SHAs and the push result
(or "local only"). Do not read logs or poll.
