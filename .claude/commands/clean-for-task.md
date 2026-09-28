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

**Sandbox-referenced paths (CC-157):** read each submodule's
`.claude/settings.stanok.json` → `sandbox.filesystem` `denyWrite`/`denyRead`
entries, resolve them against that submodule's `.claude/` dir (a `../x`
entry means `<submodule>/x`). Any clean target that is (or contains) a
resolved deny path MUST be marked `[sandbox-referenced]` in the grouped
list — deleting it breaks the W7 launch gate (rc=28) until it is recreated.

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
- **After** deletion, recreate every `[sandbox-referenced]` path that was
  removed (`mkdir -p <resolved path>`) so the W7 gate (rc=28) still passes
  (CC-157). Verify with a re-read of `settings.stanok.json` deny entries.

## 5. Commit (submodule first, then parent)
- If a submodule was cleaned: `git -C <sub> add -A && git -C <sub> commit -m "chore: clean for new task — infra only"` (the `chore:` prefix is a maintenance convention only — no git hook enforces it).
- In the parent: `git add -A` (picks up the gitlink + root changes) and commit with the same message.
- Show the final `git status --porcelain`. Ask before committing if the user prefers not to.

## Never delete (infrastructure — always keep)
`launcher/`, `hooks/`, `scripts/`, `launch.sh`, `setup.sh`,
`requirements.txt`, `CONTEXT.md`, `CLAUDE.supervisor.md`, `P0-launch.sh`, `.gitmodules`,
`.gitignore`, `.claude/`, `tickets/.gitkeep`, `specs/.gitkeep`,
and every `.gitkeep` file.
