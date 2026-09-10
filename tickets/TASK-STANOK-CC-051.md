# TASK-STANOK-CC-051 — migrate to the English skeleton base

Status: `[x] DONE` (executed by the supervisor on the host — infrastructure changes, not project code)

## Scope

1. **Rollback safety first:** tag `backup-ru-2026-09-10` in the root repo (96ffbc5) and in the
   submodule (f25489e). Rollback: `git checkout backup-ru-2026-09-10` +
   `git -C stanok checkout backup-ru-2026-09-10`.
2. **Submodule:** remove project modules (`src/`, `tests/`, `docs/` back to `.gitkeep`),
   wipe runtime artifacts (`evidence/*`, `.stanok-logs/*`, `.stanok-locks/*`).
3. **Root:** all files in English — `CLAUDE.supervisor.md` (EN role), `P0-launch.sh`
   (EN comments, machine defaults kept: server 192.168.8.131, claude bin, search env),
   `CONTEXT.md` (EN, darkcast facts), `README.md` + `.gitignore` + `.gitmodules` from the
   skeleton. `specs/` — fresh EN `STATUS.md`; `tickets/` — `.gitkeep`.
4. **Verification:** zero Cyrillic characters in `/home/hermes/darkcast` (excluding `.git`, `.venv`).

## Smokes

- `grep -rP '[\x{0400}-\x{04FF}]'` over the tree (minus `.git`/`.venv`) → empty.
- `bash -n P0-launch.sh` → OK.
- `DOCTOR_EXPECT_NO_CLOUD=1 bash stanok/hooks/doctor.sh` → 14 ok, 0 fail.
- Both trees clean (`git status --porcelain`).
