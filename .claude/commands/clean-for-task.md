---
description: Clean the current repo for a new task — keep infra, delete machine-generated code
---

Reset **THIS repo** (the current working directory — do NOT hardcode a path) to a
clean "infra-only" state for a new task: remove machine-generated code and run
artifacts, keep all infrastructure. Work in whatever repo you are invoked in.

## 1. Locate the repo (path-agnostic)
- `git rev-parse --show-toplevel` → the repo root.
- `git submodule status` → list submodules (e.g. `stanok/`).
- Clean targets live in the repo root **and** in each submodule.

## 2. Identify what to clean — do NOT delete yet
Collect the exact file list, grouped by category, with full paths:
- **Code** (machine-generated): `src/*`, `tests/*`, `docs/*` — keep each dir's `.gitkeep`.
- **Run artifacts**: contents of `evidence/`, `__pycache__/`, `*.log`.
  (Run logs live OUTSIDE the repo in `/tmp/stanok-logs` — nothing to clean in-repo.)
  `.venv/` is NOT a clean target: gitignored, but the host launcher runs from
  `stanok/.venv` — deleting it breaks the next launch until `setup.sh` re-runs.
- **Project history** (optional, for a full reset): `tickets/TASK-*.md`, `specs/STATUS.md`
  rows, `specs/AUDIT-*.md`, `specs/REDTEAM-*.md`, `specs/REVIEW-*.md`, `specs/VERIFY-*.md`.
  These are LOCAL-ONLY (gitignored since the 2026-10-13 privatization) — enumerate with
  `ls tickets/ specs/`, not git; delete with `rm` (no `git rm`).

Use `git ls-files` (tracked) + `git status --porcelain` (untracked) for git-visible
targets; for gitignored local-only files use direct directory listing.

**Evidence directory:** the launcher creates `evidence/<label>/` itself
(`launcher/cli.py:90`, `os.makedirs(..., exist_ok=True)`) — no launch gate depends
on the directory existing (the old rc=28 claim is obsolete: no such code in
`launcher/exitcodes.py`). Cleaning the CONTENTS of `evidence/` is enough.
(The old CC-157 sandbox-referenced scan is removed: `settings.stanok.json` has no
`sandbox.filesystem` deny entries — the Pod runs unsandboxed.)

**Show the user the grouped list with paths before doing anything.**

## 3. Ask before deleting (AskUserQuestion)
Ask which scope to clean:
- (a) code only (`src`/`tests`/`docs`)
- (b) code + run artifacts
- (c) code + artifacts + project history (tickets, specs/STATUS, review docs)

Confirm the shown file list. **Do not delete until the user confirms.**

## 4. Delete (only the confirmed scope)
- Tracked files: `git rm -q -- <path>`.
- Untracked files/dirs: `rm -rf <path>`.
- Always keep `.gitkeep` in `src/`, `tests/`, `docs/` so the directories survive.

## 5. Commit (submodule first; parent pin discipline)
- If a submodule was cleaned: `git -C <sub> add -A && git -C <sub> commit -m "chore: clean for new task — infra only"` (the `chore:` prefix is a maintenance convention only — no git hook enforces it).
- Parent root changes (if any): a separate commit.
- The gitlink bump is NEVER mixed into another commit: it is a single-purpose
  `chore: pin stanok <sha> — <reason>` per the parent README section "Releasing a
  Stanok version" — and the submodule is pushed to BOTH remotes before the parent
  carrying the new pin is pushed. Leaving the parent dirty (` M stanok`) until the
  release is the normal pre-publish state, not a defect.
- Show the final `git status --porcelain`. Ask before committing if the user prefers not to.

## Never delete (infrastructure — always keep)
`launcher/`, `hooks/`, `scripts/`, `k8s/`, `infra/`, `launch.sh`, `setup.sh`,
`requirements.txt`, `image-requirements.lock`, `ARCHITECTURE.md`, `.venv/`,
`CONTEXT.md`, `CLAUDE.supervisor.md`, `CLAUDE.md`, `Dockerfile`,
`README.md`, `opik-traces.py`, `patches/`, `P0-launch.sh`, `.gitmodules`,
`.gitignore`, `.claude/`, `tickets/.gitkeep`,
and every `.gitkeep` file.
