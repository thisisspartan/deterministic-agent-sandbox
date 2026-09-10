# TASK-STANOK-CC-050 — architecture mismatches, Ticket Shadowing, supervisor DoS protection, host script cleanup

Status: `[x] DONE` (executed by the supervisor on the host — infrastructure changes, not project code)

## 1. CLAUDE.supervisor.md — DoS protection (Role-Leak)

§4.3: `rc=24` (role leak — `CLAUDE.md` in the parent repo) added to the list of fatal
infrastructure codes alongside `rc=20/21/22`. `rc=24` is escalated to the human immediately;
3 retries are not burned on it.

## 2. stanok/launcher/stanok.py — Ticket Shadowing

`_resolve_ticket`: candidate order aligned with the README (project root -> machine root -> as given).
Previously the machine root had priority — an identical relative path in `stanok/tickets/`
would shadow the root `tickets/`.

## 3. stanok/hooks/verifier.sh — stored_hash fail-closed

- The blind `|| true` is gone: a lock-file read failure → explicit stderr error + `return 1`.
- Both call sites (Phase B/C) now do `|| { emit "VERIFY: FAIL (...CORRUPT...)"; exit 1; }`
  (the hook runs under `set -uo pipefail` without `-e` — without the guard a substitution
  failure would be swallowed and a corrupted lock would give a silent PASS).

## 4. stanok/launch.sh — variable rename

`PROJECT_ROOT` → `STANOK_ROOT` (the variable holds the path to the `stanok/` submodule).

## 5. stanok/sandbox-run.sh — dead bind

Removed the `--ro-bind "$REPO_ROOT/.git/config" ...` line (the whole `.git` is already
`--ro-bind` on the line above).

## 6. P0-launch.sh — reliability

- `no_proxy` untouched (`192.168.8.131,localhost,127.0.0.1` — proxy bypass for the server).
- Server check simplified: the `MODEL_LINE`/`case` indirection is gone, an empty curl
  response → immediate `exit 1`.
- Fallback on JSON parse failure: `read ... || { MODEL_NAME="?"; ... }`.

## 7. stanok/README.md — sync

Structure: `.git` is mounted strictly read-only (`--ro-bind`); the outdated tmpfs mention
for `.git/hooks` is removed. The ticket resolution order (:31) now matches the code.

## Smokes (stage 3)

- resolve-priority: a ticket in both parent and machine root resolves to the parent
  (SMOKE-RESOLVE-OK), artifacts removed, `stanok/tickets` removed.
- stored_hash (sed extraction): missing → empty/rc=0; valid lock → hash; unreadable file
  → rc=1 + stderr (SMOKE-HASH-MISSING-OK, SMOKE-HASH-READ-OK, SMOKE-HASH-CORRUPT-OK).
- `bash -n` launch.sh / sandbox-run.sh / P0-launch.sh — OK.
- `DOCTOR_EXPECT_NO_CLOUD=1 bash hooks/doctor.sh` → 14 ok, 0 fail.
- `git status --porcelain` — both trees clean.
