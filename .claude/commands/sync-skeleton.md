---
description: Interactively sync this repo's infrastructure into skeleton-pub (diff preview + push option)
---

Sync **this repo** (SRC = current working directory, path-agnostic) into **skeleton-pub**
(DST = `/home/hermes/skeleton-pub`, always the destination). Only infrastructure is
synced; machine-generated code (`stanok/src|tests|docs`) and project history (tickets,
review docs, evidence) are excluded. Clean templates stay clean.

## 1. Determine the repos
- SRC = the PARENT repo root, from wherever you are:
  `git rev-parse --show-superproject-working-tree` (inside a submodule this prints the
  parent root; at the parent root it prints nothing) — if the output is empty, fall
  back to `git rev-parse --show-toplevel`. Do NOT hardcode a path.
- DST = `/home/hermes/skeleton-pub` (fixed).
- The sync engine is `"$SRC/.claude/sync-skeleton.sh"`.

## 2. Preview the diff (do NOT apply yet)
Set and EXPORT the vars as SEPARATE statements first, THEN run. Two pitfalls:
a `VAR=... cmd "$VAR/..."` one-liner is WRONG (the shell expands `$SRC` before the
prefix assignment takes effect → `/.claude/sync-skeleton.sh` → exit 127); and a plain
(non-exported) assignment is invisible to the script, which then re-derives SRC from
its OWN cwd — from a subdirectory that lands on the submodule root ("SRC has no
stanok/", exit 1).
    SRC="$(git rev-parse --show-superproject-working-tree)"
    [ -z "$SRC" ] && SRC="$(git rev-parse --show-toplevel)"
    export SRC
    DST="/home/hermes/skeleton-pub"
    "$SRC/.claude/sync-skeleton.sh" --diff
It prints, per category, the files to ADD / MODIFY / REMOVE (submodule infra + top-level
infra) and a `TOTAL changes:` count. **Show the user this list.**
- If `TOTAL changes: 0` → tell the user "already in sync, nothing to do" and stop.

## 3. Ask how to proceed (AskUserQuestion)
"Both repos" = the two DST repos: skeleton-pub (top) and its submodule.
SRC (this repo) is READ-ONLY for the sync — never committed, never pushed.
The mirror is LOCAL-ONLY by default (the script's default since 2026-10-13): the
parent pushes its own published commits to GitHub, and the skeleton's sync commits
intentionally diverge from that history — a push of a sync commit is usually
REJECTED (incident 2026-10-13, parallel submodule commit e54f014).
- (a) **Sync (local only)** — apply + commit skeleton-pub (top + submodule), NO push.
- (b) **Sync + push** — same + push both to GitHub; bootstrap case only, expect a
  rejection unless the histories genuinely match.
Do not apply until the user chooses.

## 4. Apply
Re-use the `SRC`/`DST` vars from step 2 (do NOT inline-assign them on the same
line as the command — see the pitfall note in step 2).
- (a): `"$SRC/.claude/sync-skeleton.sh"`
- (b): `"$SRC/.claude/sync-skeleton.sh" --push`

Report the final status: the submodule + top-level commit SHAs and the push result
(or "local only"). Do not read logs or poll.
