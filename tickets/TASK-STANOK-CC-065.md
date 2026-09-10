# TASK-STANOK-CC-065 — Nested-sandbox mount layer: /tmp fix + mount-preflight (rc=23)

## Executor
**Supervisor, NOT the machine.** The machine cannot do this: `sandbox-run.sh`,
`hooks/`, `launcher/stanok.py` and `.claude/settings.stanok.json` are outside its
reach (`denyWrite`, read-guard, bash-gate → `run.sh` only). Execute this in the
control-room session; verify on the host.

## Background / problem

The machine runs under TWO nested bubblewrap layers:

1. **Outer** — `stanok/sandbox-run.sh`: `--ro-bind / /`, `--tmpfs /tmp`, then the
   repo mounted read-only with writable carve-outs (`src/ tests/ docs/ evidence/
   .stanok-logs/`).
2. **Inner (native)** — claude-code 2.1.88's own sandbox (`sandbox.*` in
   `.claude/settings.stanok.json`): `--ro-bind / /`, then it binds its
   `allowWrite` set (`'.'`, `getClaudeTempDir()`) read-write.

Two regressions have now been produced by the same seam — "the inner layer
ro-binds a tree the outer layer prepared":

- **#1 (FIXED, submodule `67934e8`):** for a `denyWrite` path that does not
  exist, the inner runtime must CREATE the bwrap mountpoint → `bwrap: Can't
  create file at <repo>/.claude/settings.json: Read-only file system`
  (36 hits across cc061-063). Fixed by pre-creating the 16 stub targets.
- **#2 (THIS TICKET):** `/tmp` becomes read-only inside the old sandbox.
  `getClaudeTempDir()` = `/tmp/claude-$(id -u)`. The outer `--tmpfs /tmp` wipes
  the host's `/tmp/claude-1000`, so it does not exist when the inner runtime
  builds its argv — and the runtime **silently skips non-existent write paths**
  (`cli.js`, `KC_`: `"Skipping non-existent write path"`). So `/tmp` is never
  re-bound rw, and claude cannot write its cwd-tracking file:
  `(eval):1: read-only file system: /tmp/claude-1000/cwd-3b9a` (5 hits in cc064).
  The model then concluded its cwd was `/tmp/claude-1000/cwd-3b9a`, wasted a
  `Read` there, and burned reasoning on the confusion.

## Goal

1. Fix the `/tmp` mountpoint so claude's temp/cwd dir is writable inside the
   sandboxed session.
2. Add a cheap **mount-preflight** that turns this whole failure class into a
   fast, explicit host-side error (new **rc=23**) instead of a silent runtime
   failure that costs a whole model turn.

## Verified facts (do not re-derive)

Outer layer, current `sandbox-run.sh`:
```
--ro-bind / /  ...  --tmpfs /tmp  ...  --ro-bind "$REPO_ROOT" "$REPO_ROOT" ...
```
Reproduction (host, inside the real `sandbox-run.sh`):
```
$ ./sandbox-run.sh /bin/bash -c 'ls -d /tmp/claude-1000 || echo MISSING_INSIDE_OUTER'
MISSING_INSIDE_OUTER
```
and the inner-native-equivalent write fails:
```
$ bwrap --ro-bind / / --dev /dev -- /bin/bash -c 'mkdir -p /tmp/claude-1000'
mkdir: cannot create directory '/tmp/claude-1000': Read-only file system
```
Fix candidate, validated end-to-end on this host:
```
$ bwrap --bind / / --tmpfs /tmp --dir /tmp/claude-1000 ... \
    /bin/bash -c 'bwrap --ro-bind / / --dev /dev --bind /tmp/claude-1000 /tmp/claude-1000 \
      /bin/bash -c "echo wrote > /tmp/claude-1000/cwd-x && cat /tmp/claude-1000/cwd-x"'
wrote
```

## Part 1 — `/tmp` fix (one line, correct order)

In `sandbox-run.sh`, immediately after `--tmpfs /tmp` in the base `BWRAP_ARGS`,
add a directory creation for claude's temp dir:

```bash
--tmpfs /tmp
--dir "/tmp/claude-$(id -u)"
```

Requirements:
- **Respect `CLAUDE_CODE_TMPDIR`.** If it is set, `getClaudeTempDir()` is
  `$CLAUDE_CODE_TMPDIR/claude-$(id -u)`, not `/tmp/claude-...` — compute the dir
  the same way the runtime does, not a hardcoded `/tmp`.
- Keep the order: the `--dir` must come after `--tmpfs /tmp` (the tmpfs wipes
  the path; the dir must be created on top of it).
- Comment it with the "why" (inner ro-binds `/`, runtime skips non-existent
  write paths), same style as the existing stub block.

Caveat to write down (do NOT state this as "architecturally proven"): the
equality `outer $(id -u) == inner getClaudeTempDir()` holds only while neither
bwrap call remaps UIDs (`--unshare-user`). It was validated empirically on this
host's configuration, nothing more.

## Part 2 — mount-preflight (new rc=23, host-side, model-free)

Add a preflight that runs BEFORE `exec bwrap` in `sandbox-run.sh` (so before the
runner starts and long before any model turn). It must:

1. Build the same nested-argv shape the inner runtime produces — `--ro-bind / /`
   plus a `--ro-bind <path> <path>` for each pre-created stub target — and run a
   trivial command (`/bin/true`) for each of:
   - the 16 stub targets: `.gitconfig .gitmodules .bashrc .bash_profile .zshrc
     .zprofile .profile .ripgreprc .mcp.json .claude/settings.json
     .claude/settings.local.json .vscode .idea .claude/skills .claude/commands
     .claude/agents`
   - `/tmp/claude-$(id -u)` (the Part 1 path)
   This replicates the inner mount operations **without the model** — a literal
   "one real Bash tool call" cannot be exercised host-side (that requires a
   model turn), so the argv-faithful probe is the host-side approximation.
2. On any failure: print the failing path + bwrap's stderr, and exit **rc=23**.
   Do not proceed to the run.

### rc=23 wiring (do not skip)
- This is an **infrastructure** failure, like role-leak/dirty-tree — not a
  ticket defect. Reserve a distinct code: **rc=23 = nested-sandbox mount
  preflight failed**.
  - **Why 23 and not 25:** `rc=25` is *retired* — it historically meant
    "python3 disappeared", and `hooks/doctor.sh:65` documents it as
    "equivalent to the old rc=25". Do not re-use it. `rc=23` has zero
    occurrences anywhere in the tree, so it is free. (Supervisor: sanity-check
    23 against your own memory before wiring.)
- Add rc=23 to the immediate-escalation list in **§4 of
  `CLAUDE.supervisor.md`**, next to rc=20/21/22/24. The same lesson applied to
  rc=24 must be applied here in the same change.
- Document rc=23 in the gate-order list in `stanok/README.md` ("How it works")
  as a **host-side** gate emitted by `sandbox-run.sh` (the existing list covers
  runner-emitted codes).

### Scope honesty (write this into the ticket comment / docs)
The preflight catches **recurrence of the known classes only** — the fixed list
of 16+1 paths. It does **not** protect against a NEW path introduced by a future
claude-code version (the very thing that produced regressions #1 and #2). It is a
regression guard for what we have already found, **not** a fix for the
architectural fragility of the two-layer seam. Do not read a green preflight as
"the nested sandbox is safe".

## Out of scope / invariants
- **IRON STOP stands:** do not delete or dismantle `sandbox-run.sh`; do not
  remove the outer layer. Both layers stay.
- Do not touch the llama-server, `settings.stanok.json` hook wiring, the
  verifier/bash-gate/read-guard hooks, or `launcher/stanok.py`.
- No new external dependencies (bash + bwrap + coreutils only).

## Acceptance criteria
- `grep -R "claude-\$(id -u)" sandbox-run.sh` shows the `--dir` line immediately
  after `--tmpfs /tmp`.
- Preflight is called before `exec bwrap`; a deliberately broken path (e.g.
  temporarily remove one stub) makes `sandbox-run.sh` exit **23** with a clear
  message and NOT start a run.
- With everything in place: `./sandbox-run.sh /bin/bash -c 'mkdir -p
  /tmp/claude-$(id -u) && echo ok'` prints `ok` (no EROFS).
- Re-run a real machine ticket (background) and confirm: 0 occurrences of
  `read-only file system: /tmp/claude-` in the session log, and the model no
  longer reports cwd as a `/tmp/claude-*` path.
- `sandbox/*.sh` shell syntax clean (`bash -n`).

## Notes for the final report (≤ 6 lines)
1. TASK: DONE / PARTIAL
2. Files: sandbox-run.sh, CLAUDE.supervisor.md, stanok/README.md
3. rc=23 introduced + documented in §4
4. Preflight: negative control (broken path → rc=23) reproduced
5. Real-run evidence: /tmp/claude-* errors = 0, cwd correct
