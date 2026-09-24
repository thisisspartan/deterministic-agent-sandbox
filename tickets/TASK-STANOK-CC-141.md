# TASK-STANOK-CC-141 — the CLI's per-uid tmp dir must exist inside the container (Слой 2)

Supervisor-executed (`launcher/` is RO in the container). Closes the long-open
**"Слой 2"** nested-sandbox defect, resurfaced in the operator's SMOKE-01 trace
(session `6d92f0bb-a6b3-443d-aa51-f1213a6b1d9e`, label `follow-smoke-retry1`).

## Incident

The trace shows **8×** `/bin/bash: line 4: /tmp/claude-1000/cwd-f835: Read-only
file system` on the session's Bash calls, while the run itself is healthy
(`rc=1 / verifier=PASS / probe_result=NO-OP-PASS / writes=0` — the ticket was
pre-satisfied). It is the same string recorded as OPEN in `CONTEXT.md:1404`
("ПЕРВЫЙ Bash-вызов в сессии … во второй `--bind` ЕСТЬ"). The CC-112
re-check (CONTEXT.md:1516) only looked at `launch.log`, so it declared the
defect "not blocking" — it never checked the session transcript.

Root cause, source-verified in `cli.js` 2.1.88:

- `DC_()` builds `allowOnly = [...yn6(), ...filesystem.allowWrite]`; the
  settings builder seeds `allowWrite` with `[".", AC()]`, and
  `AC() = Wk(realpathSync(CLAUDE_CODE_TMPDIR||"/tmp"), Na1())` with
  `Na1() = "claude-<getuid()>"` → **`/tmp/claude-<uid>/` IS in allowOnly**.
- `KC_()`'s bind loop skips non-existent paths:
  `if(!KO.existsSync(M)){ O7("Skipping non-existent write path"); continue }`.
  The dir is created lazily, so the **first** invocation emits no
  `--bind /tmp/claude-<uid>` and the cwd-file write lands on `--ro-bind / /`
  → EROFS; by the second invocation the dir exists and is bound.
- The harness's host-side pre-create (`sandbox.py`) was **invisible**: nothing
  binds `/tmp` into the container. `launch.sh` pre-created the same path on the
  host with the same (wrong) rationale.
- Env note: `sandbox.py` sets `CLAUDE_TMPDIR` (the TMPDIR the nested runtime
  exports — `aG8()`), while `sandboxTmpDir`/`AC()` read `CLAUDE_CODE_TMPDIR`.
  Leaving the latter unset makes both agree on `/tmp/claude-<uid>`; setting it
  to the same path would **double-nest** it to `/tmp/claude-<uid>/claude-<uid>`.
  No env change is made.

## Change

- `sandbox.py`: drop the host `makedirs`/`chmod`; add
  `--tmpfs /tmp/claude-<uid>:uid=<uid>,gid=<gid>,mode=700,exec` next to the
  `/home/stanok` HOME tmpfs. The container uid equals ours (`--user`), so the
  path matches `Na1()`. A tmpfs (not a host bind) keeps it hermetic, kills it
  with the container, and — the whole point — makes it exist **before** the CLI
  starts, so the bind is emitted from the very first invocation. `exec` is
  required for parity: the nested runtime exports `TMPDIR=<this dir>`
  (`aG8()`), so a tool/test writing a temp script to `$TMPDIR` and running it
  must not hit docker's default `noexec` (upstream `/tmp/claude` is a plain
  dir) — the cwd-file itself is a `>|` redirect target, never executed.
- `launch.sh`: comment corrected; the host-side create stays for the host
  (no-sandbox) path.

## Verification

- `py_compile` (sandbox.py), `bash -n` (launch.sh).
- Manual reproduction with docker (no model needed):
  - negative: container `ls /tmp/claude-1000` → absent (host pre-create
    invisible); `mkdir -p` outside bwrap then `bwrap --ro-bind / /` writing the
    cwd-file → the exact `Read-only file system` string;
  - positive: `--tmpfs /tmp/claude-1000:uid=…,gid=…,mode=700,exec` →
    `DIR-EXISTS`, nested `bwrap --ro-bind / / --bind /tmp/claude-1000 …` →
    write OK, and a temp script in the dir runs (no `noexec`).
- New `launcher/tests_harness/test_tmp_bind.py` (4 tests): argv carries exactly
  two `--tmpfs` (HOME + the CLI tmpdir) and **no** `-v` bind targeting
  `/tmp/claude-<uid>`; e2e docker: the dir exists before any command runs,
  nested bwrap can write it, and a temp script under it is executable; e2e
  negative control: without the tmpfs that same write is EROFS (the regression
  cannot silently return).
- `bash hooks/doctor.sh` — **162 passed, 0 skipped on a clean tree** (158 + 4).

## Non-goals / residuals

- Only the container path is fixed; host mode keeps `launch.sh`'s pre-create.
- The final e2e is a live machine run: `launch.log` free of
  `Read-only file system` (and the session transcript, which the CC-112 check
  overlooked). The proof here is at the exact layer the defect lives in
  (docker + nested bwrap), which needs no model.
- No change to `yn6()`/`allowWrite` semantics, and `CLAUDE_CODE_TMPDIR` is
  deliberately left unset (see above).
