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
- **Run artifacts**: `evidence/`, `.stanok-logs/`, `__pycache__/`, `.venv/`, `*.log`.
- **Project history** (optional, for a full reset): `tickets/TASK-*.md`, `specs/STATUS.md`
  rows, `specs/AUDIT-*.md`, `specs/REDTEAM-*.md`, `specs/REVIEW-*.md`.

Use `git ls-files` (tracked) + `git status --porcelain` (untracked) to build the list.
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

## 5. Commit (submodule first, then parent)
- If a submodule was cleaned: `git -C <sub> add -A && git -C <sub> commit --no-verify -m "chore: clean for new task — infra only"`.
- In the parent: `git add -A` (picks up the gitlink + root changes) and commit with the same message.
- Show the final `git status --porcelain`. Ask before committing if the user prefers not to.

## Never delete (infrastructure — always keep)
`launcher/`, `hooks/`, `scripts/`, `launch.sh`, `sandbox-run.sh`, `setup.sh`,
`requirements.txt`, `CONTEXT.md`, `CLAUDE.supervisor.md`, `P0-launch.sh`, `.gitmodules`,
`.gitignore`, `.claude/`, `tickets/.gitkeep`, `specs/.gitkeep`,
and every `.gitkeep` file.
