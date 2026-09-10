# TASK-STANOK-CC-053 — KV cache metrics, tdd_gate rename handling, watchdog semantics, gate-order sync

Status: `[x] DONE` (executed by the supervisor on the host — infrastructure change, not project code)

Note: submitted as "CC-051", but CC-051 (migration) and CC-052 (`--host` flag) are already
taken — registered as CC-053 (next free per CONTEXT.md).

## 1. stanok/launcher/stanok.py

- **cache_hit_rate formula** (lines ~490, ~498): the context denominator now includes
  `cache_creation_input_tokens` — session and per-turn hit rates are mathematically exact.
- **tdd_gate()** (line ~324): the porcelain parser now extracts the target path for rename
  status (R) (`path.split(" -> ")[-1]`) and strips git quotes (`path.strip('"')`); `R` is
  added to the tracked statuses, so renamed test files are gated by the target path
  (fail-closed).
- **Watchdog docstring** (lines 1–12): item 5 now states that the turn timeout
  (default 1200s) is a terminal DoS circuit breaker — `asyncio.shield()` keeps the turn
  task alive past `wait_for`, so `client.interrupt()` runs cleanly and summary.json is
  written with the TURN-TIMEOUT code (rc=1) without the process dying on CancelledError.
- **no_proxy default** (line 44): `"127.0.0.1,localhost,127.0.0.1"` → `"127.0.0.1,localhost"`.

## 2. P0-launch.sh + stanok/README.md

- P0-launch.sh: the default no_proxy (HOST=127.0.0.1) is deduped to
  `"127.0.0.1,localhost"`; the battle value (HOST=192.168.8.131) stays
  `"192.168.8.131,localhost,127.0.0.1"` untouched. P0 stays byte-identical in
  darkcast and skeleton-pub.
- stanok/README.md: the documented gate order now matches `main()`:
  label-guard (rc=15) -> ROLE-LEAK (rc=24) -> ticket (rc=13) -> dirty-tree (rc=22)
  -> lock (rc=21) -> pre-flight (rc=20).

## Smokes

- SMOKE-CACHE-RATE-OK (formula with cache_creation + zero-context guard).
- SMOKE-RENAME-PARSE-OK (M / ?? / R / quoted-R extraction).
- `python3 -m py_compile stanok/launcher/stanok.py` — PY-SYNTAX-OK.
- `bash -n P0-launch.sh` — BASH-SYNTAX-OK.
- `DOCTOR_EXPECT_NO_CLOUD=1 bash stanok/hooks/doctor.sh` — 14 ok, 0 fail.
- `git status --porcelain` — both trees clean; P0 `diff` empty.
