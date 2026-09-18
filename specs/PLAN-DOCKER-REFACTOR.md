# PLAN — Docker refactor of the stanok machine (bwrap → container boundary)

Status: **IN PROGRESS — B1 hybrid adopted 2026-09-18. Steps 1–4, 6–9 done (2026-09-18): infra committed (stanok `9422048`), image built, static checks green, NO-OP smoke PASS (`smoke02-docker3`: probe_result=NO-OP-PASS, verifier=PASS, 1 turn, 0 writes, no orphan containers). Awaiting user's `stanok.py` patch (step 5); step 10 (rebuild smoke) is the user's call.**

Extra fixes found during steps 7–9 (not in the original gap list):
- `--cpus` default 4 → 2 (host has 2 CPUs; docker rejects higher).
- claude install is a multi-hop symlink chain (`bin/claude` → npm package `cli.js` →
  `git/claude-code-2.1.88/cli.js`); sandbox-run.sh now mounts EVERY directory in the
  chain, not just shim dir + final dir (intermediate hop dangled → `command -v claude` failed).
- Host `$PY` is `$REPO_ROOT/.venv/bin/python` (symlink → `/usr/bin/python3`); inside the
  container that lands on the image python 3.11 with the host venv's 3.12 site-packages
  (read-only) → `No module named claude_agent_sdk`. sandbox-run.sh remaps the venv path
  to the image system python (SDK is baked into the image).
- CLI needs `socat` (allowedDomains bridge sockets) in addition to `bwrap` — startup
  hard-fail verified: "dependencies are missing: socat not installed". Added to Dockerfile.

Decisions (§2, confirmed):
1. HOME: **(a) tmpfs** — ephemeral, no host coupling.
2. Domain isolation: **B1 HYBRID** (revised 2026-09-18 after empirical verification, see §5) —
   native sandbox (bwrap) runs INSIDE the container: `sandbox.enabled: true`,
   `enableWeakerNestedSandbox: true`, `allowedDomains` restored. Container keeps
   cap-drop=ALL + no-new-privileges; docker seccomp/apparmor profiles are
   unconfined (required for bwrap, see §5 matrix).
3. Old tickets: **(a) new format only**; doctor.sh updated in the follow-up wave.
4. Verifier hook: **kept** (PostToolUse Write|Edit → hooks/verifier.sh).

## 0. Inputs and verified host facts

Files under review (`tmp/`):
- `tmp/Dockerfile` (91 lines) — image: debian:bookworm-slim, git/curl/build-essential/python3/pip/venv,
  `claude-agent-sdk==0.2.139`, user `stanok` (10001), no ENTRYPOINT (command always passed by the runner).
- `tmp/sandbox-run.sh` (149 lines) — Docker replacement of the bwrap `sandbox-run.sh`; same name, same
  calling contract (`exec "$SANDBOX" "$@"` from `launch.sh:120,135`).
- `tmp/CLAUDE.md` (83 lines) — machine role: four writable dirs (src/tests/docs/scripts), native
  UNRESTRICTED Bash, `scripts/run.sh {list,test,smoke}` contract, stack-neutral prose.

Verified host facts (2026-09-18):
- node **v22.22.3** — real file at `/usr/bin/node` (so `HOST_NODE_DIR = /usr/bin`).
- python3 = `/usr/bin/python3.12` (Ubuntu 24.04); the image is bookworm (python3.11).
- `.venv/bin/python → python3 → /usr/bin/python3` (absolute); `pyvenv.cfg`: `home = /usr/bin`, 3.12.3.
- docker 29.1.3 present; no running containers.
- claude: shim `/home/hermes/.npm-global/bin/claude` → `/home/hermes/git/claude-code-2.1.88/cli.js`
  (shebang `#!/usr/bin/env node`; dir holds cli.js, vendor/, source/ — a standalone checkout, NOT node_modules).
- SDK pin **0.2.139** — identical in `requirements.txt` and the Dockerfile.
- `stanok/` git: clean, HEAD `bb87fae`.
- Tickets: 4, ALL old format (`module:` / `reset: none`), all completed/historical.
- `hooks/doctor.sh`: placeholder tickets with `module: doctor` (lines 73, 127); bwrap references.

## 1. Verified gaps — the three files do NOT work as-is

Each item verified against the current code + this host.

1. **Parent mount missing → rc=13 on every launch (FATAL).**
   `stanok.py:_resolve_ticket` (1035–1047) resolves the ticket against `dirname(REPO_ROOT)` = project
   root (`darkcast/tickets/...`) first. The bwrap `sandbox-run.sh` ro-binds `$PARENT_DIR/tickets`
   (lines 93–95); the Docker version mounts nothing from the parent → "Ticket not found" (rc=13).
   Side effect: the role-leak gate (rc=24, `stanok.py:1114–1116`) checks `dirname(REPO_ROOT)/CLAUDE.md` —
   invisible inside the container → the gate is silently disabled.
   Fix: `-v "$PARENT_DIR:$PARENT_DIR:ro"` before the REPO_ROOT mount (faithful port; keeps both
   ticket resolution and the rc=24 gate live).

2. **`compgen -e` instead of `compgen -v` → zero STANOK_* env vars passed (FATAL for claude).**
   `sandbox-run.sh:93` — `compgen -e` lists EXECUTABLES, not env vars → the loop body never runs.
   `STANOK_CLAUDE_BIN` is lost → `CLAUDE_BIN = shutil.which("claude") or "claude"` (`stanok.py:44`) →
   claude is not on the container PATH → the SDK cannot spawn the CLI.
   Fix: `compgen -v`.

3. **Node mount overlays `/usr/bin` → breaks the launcher's python (FATAL).**
   `HOST_NODE=/usr/bin/node` → `HOST_NODE_DIR=/usr/bin` → `-v /usr/bin:/usr/bin:ro` replaces the image's
   `/usr/bin` with the host's. Image `python3` (→python3.11) is hidden; host `python3→python3.12` has no
   stdlib in the image (bookworm ships 3.11). Both the image `python3` and the venv python
   (`.venv/bin/python3 → /usr/bin/python3`) break.
   Fix: file-level mount `-v /usr/bin/node:/usr/local/bin/node:ro` (node v22 deps libssl3/libstdc++6 are
   in bookworm-slim; verify at build). Never directory-mount the dir containing node when it is a
   system dir.

4. **Container PATH lacks node/claude → claude shim cannot start (FATAL).**
   The shim's shebang `#!/usr/bin/env node` resolves node via the container PATH (image default:
   `/usr/local/bin:/usr/bin:/bin`). Host dirs are mounted but not on PATH.
   Fix: `-e PATH="<node location>:<claude shim dir>:/usr/local/bin:/usr/bin:/bin"` (the
   `/usr/local/bin/node` mount covers node; the shim dir must exist for the `STANOK_CLAUDE_BIN` path).

5. **`HOST_CLAUDE_PKG_DIR` = `/home/hermes/git` → leaks user's git repos + `agnt/.env` to the model (SECURITY).**
   `dirname(dirname(cli.js))` = `/home/hermes/git` (claude is a standalone checkout, not under
   node_modules). Mounting it ro exposes all repos incl. the search API keys.
   Fix: mount ONLY the shim dir (`/home/hermes/.npm-global/bin`) + the resolved cli.js dir
   (`/home/hermes/git/claude-code-2.1.88`).

6. **HOME not writable → CLI cannot write `~/.claude`, `~/.claude.json` (LIKELY FATAL).**
   The bwrap version bound `$HOME/.claude` rw + `.claude.json` rw + tmpfs `$HOME` (lines 85–89).
   The Docker version mounts nothing from `$HOME`; image `HOME=/home/stanok` is owned by uid 10001,
   process runs as uid 1000.
   Fix: decision §2.1 — tmpfs HOME vs bind host `~/.claude`.

7. **`STANOK_HOST_PID` missing → `launch.sh status` broken (FATAL for the supervisor loop).**
   Marker pid (`stanok.py:879–883`) falls back to the CONTAINER-internal pid; host-side
   `cmd_status` `_pid_alive()` (977) checks it in the host pid namespace → wrong state. The
   supervisor's blocking wait (`while status | grep running`) breaks.
   The bwrap version set `--setenv STANOK_HOST_PID $$` (line 146).
   Fix: `-e STANOK_HOST_PID="$$"` (the exec'd docker CLI process stays alive while the container runs).

8. **`exec` discards the reaper trap (the stated guarantee is false).**
   `trap cleanup EXIT INT TERM` (line 130) is set BEFORE `exec docker run` (line 138) — exec replaces
   the process image; the trap never fires. Attached-mode docker forwards SIGINT/SIGTERM into the
   container (with `--init`), so stop mostly works via python's handler — but the file's reaper
   claim is dead code.
   Fix: drop `exec` (run `docker run` as a child, capture rc, `exit $rc`) so the trap works as designed.

9. **`settings.stanok.json` is NOT in the change set but MUST change (MANDATORY).**
   - `permissions.deny` contains `"Bash"` (line 40) → the model cannot run tests at all. Remove;
     add `"Bash"` to allow.
   - `permissions.allow` contains `"mcp__run__run"` (line 37) → the tool disappears. Remove.
   - `sandbox.enabled: true, failIfUnavailable: true` (78–79) → the image has no bwrap, and bwrap
     CANNOT work under cap-drop=ALL + no-new-privileges + docker default seccomp (unshare blocked)
     → the CLI hard-fails at startup. Must be `enabled: false` (the container IS the boundary).
   - Consequence: `sandbox.network.allowedDomains` (line 82) dies with it → the model's Bash has FULL
     network via `--network=host`. The claim "domain isolation remains" is FALSE (§2.2).

10. **The `stanok.py` patch is bigger than the ticket header.**
    The header change (208–235) is necessary but not sufficient:
    - Remove the run MCP tool: `CURATED_TOOLS` (57–60: `"mcp__run__run"` → `"Bash"`),
      `_build_run_mcp_server()` (487–538), `mcp_servers={"run": ...}` (554), comment 57–59.
    - Retry prompt (706–709): "Create the reference *.test.js" → stack-neutral wording.
    - **NEW SAFETY REQUIREMENT for literal paths:** the old derived format was structurally safe
      (src/tests/docs prefixes). Literal `files:` paths need validation (relative, no `..`, inside
      {src,tests,docs,scripts}) — otherwise `prepare_workspace` quarantine (251–259, `shutil.move`)
      could destroy arbitrary host files a ticket declares (e.g. `impl: /etc/passwd`).
    - (cosmetic) bwrap mentions (239, 1125–1126); `node:internal` filter (275–276, harmless).

11. **Old-format tickets break (rc=13) after the parser change.**
    All 4 tickets in `darkcast/tickets/` use `module:`/`reset: none`; `doctor.sh` placeholders too
    (73, 127). All completed/historical — but the doctor breaks. Decision §2.3.

12. **Dockerfile comments reference `docker-run.sh`** (lines 8, 13, 34, 42, 46, 50, 75, 86, 90) —
    the file is `sandbox-run.sh`. Cosmetic comment fix.

## 2. Decisions needed before execution

1. **HOME inside the container.**
   (a) `--tmpfs` HOME — ephemeral, no host coupling, per-run session history lost. **Recommended.**
   (b) bind host `$HOME/.claude` rw — faithful bwrap port, shares session history with the host's
       interactive claude.
2. **Domain isolation.** With the native sandbox off, `allowedDomains` is gone; `--network=host` =
   full network for the model's Bash. Confirm acceptance (the alternative — bwrap in the image — is
   impossible under the chosen hardening).
3. **Old tickets.**
   (a) new format only; old tickets are historical; doctor updated in the follow-up wave. **Recommended.**
   (b) dual-format parser (backward compat).
4. **Verifier hook** (PostToolUse `Write|Edit` → `hooks/verifier.sh`, `settings.stanok.json:97–103`):
   keep (red-phase feedback; compatible with native Bash) — confirm. It was not in the removal list.

## 3. Execution plan (after decisions)

1. **Fix `tmp/sandbox-run.sh` in place** (items 1–8): parent ro mount, `compgen -v`, node file-mount
   to `/usr/local/bin/node`, container PATH, claude mount scope (shim dir + cli.js dir, NOT
   `/home/hermes/git`), `STANOK_HOST_PID`, drop `exec` (trap works). Show the diff before placement.
2. **Fix Dockerfile comments** (`docker-run.sh` → `sandbox-run.sh`).
3. **Place the files:**
   - `tmp/Dockerfile` → `stanok/Dockerfile` (new)
   - `tmp/sandbox-run.sh` → `stanok/sandbox-run.sh` (replace, chmod +x)
   - `tmp/CLAUDE.md` → `stanok/CLAUDE.md` (replace)
4. **Edit `stanok/.claude/settings.stanok.json`:** Bash allow, run-tool removal, `sandbox.enabled=false`.
5. **`stanok.py`:** hand over the current file (`stanok/launcher/stanok.py`, 1141 lines, HEAD
   `bb87fae`) + the line ranges (§1.10); the user writes the patch inline; I apply it.
6. **Commit:** `stanok/` infra commit; bump the darkcast root gitlink. (`tmp/` — delete or keep, user's call.)
7. **`docker build -t stanok-machine:latest -f stanok/Dockerfile stanok/`.**
8. **Static container checks via the real script (no model):** `bash stanok/sandbox-run.sh <cmd>` with:
   `id`, `python3 -V`, `node -v`, claude discoverability, rw check in `src/`, EROFS on `.git`,
   parent `tickets/` visible, parent `CLAUDE.md` visible (rc=24 gate live).
9. **Pipeline smoke (new format):** a `reset: none` NO-OP ticket → full run (container → claude →
   model turn → verifier → summary.json). Checks: `status` shows running (STANOK_HOST_PID), done +
   summary, reaper on stop (`docker ps` empty after stop).
10. **(user's call) real rebuild smoke:** new-format ticket with `files:` impl/test/docs for `smoke`
    → quarantine → TDD rebuild → rc=0.
11. **Follow-up wave (after the core works):** `doctor.sh` (Docker + new header format),
    `stanok/README.md`, root README quickstart (docker build step), `setup.sh` (docker build),
    `scripts/run.sh` header comment (stale "MCP run tool" prose); then sync to skeleton-pub.

## 5. Findings: bwrap inside the container (verified 2026-09-18)

Initial claim "bwrap CANNOT work under cap-drop=ALL + no-new-privileges + docker
default seccomp" was correct for the DEFAULT config but WRONG as "impossible in
principle". Empirical matrix (debian:bookworm-slim, bubblewrap 0.9.0, uid 1000,
`bwrap --bind / / --dev-bind /dev /dev [--proc /proc] --unshare-pid --unshare-uts true`):

| Container config | Result |
|---|---|
| docker defaults (seccomp + apparmor) | FAIL — `unshare` blocked by seccomp |
| + `--security-opt seccomp=unconfined` | FAIL — `make / slave: EPERM` (docker-default AppArmor) |
| + `--security-opt apparmor=unconfined` | FAIL — `Can't mount proc on /newroot/proc: EPERM` |
| + no `--proc /proc` | **PASS (rc=0)** |
| + no `--proc` + `--security-opt=no-new-privileges` | **PASS (rc=0)** — cap-drop=ALL + nnp can stay |

Host control: the same bwrap command as the host user → rc=0 (the current machine works).

CLI evidence (pinned claude-code 2.1.88, grepped, not assumed):
- `source/src/utils/sandbox/sandbox-adapter.ts` — the `sandbox` settings block is the
  native sandbox, wrapping `@anthropic-ai/sandbox-runtime`.
- `cli.js` Linux path builds exactly:
  `bwrap --new-session --die-with-parent [--unshare-net + http/socks bridge sockets +
  proxy env] <fs ro-bind/bind args> --dev /dev --unshare-pid [--proc /proc] -- bash -c <cmd>`.
- **`sandbox.enableWeakerNestedSandbox`** — cli.js description: *"Enable weaker nested
  sandbox mode (for Docker environments)"*. Its only effect in the bwrap build:
  **skips `--proc /proc`** — precisely the step that fails inside a container.
  Anthropic explicitly supports our scenario.
- Network isolation mechanism: `--unshare-net` + a local HTTP/SOCKS bridge process
  spawned by the CLI; sandboxed commands reach the outside only through the bridge,
  which enforces `allowedDomains`.
- Degradation note: unix-socket-blocking seccomp BPF binaries ship in
  `@anthropic-ai/sandbox-runtime` (`vendor/seccomp/`); our CLI checkout's vendor/ has
  only audio-capture + ripgrep → CLI logs a warning and disables unix-socket
  blocking only. Non-fatal.

Consequences for the change set (B1):
- Dockerfile: `+ bubblewrap` in apt (failIfUnavailable=true hard-fails without it).
- sandbox-run.sh: `+ --security-opt seccomp=unconfined --security-opt apparmor=unconfined`.
- settings.stanok.json: `sandbox: { enabled: true, failIfUnavailable: true,
  enableWeakerNestedSandbox: true, network: { allowedDomains: [...] } }`.
- Trade-off accepted: docker seccomp + apparmor profiles off; remaining layers =
  cap-drop=ALL, no-new-privileges, bwrap user-namespace per command, resource limits,
  host-side verify_gate.
- Model's Bash is now domain-restricted (no more full network): allowlist =
  192.168.8.131, localhost, 127.0.0.1 + package registries (pypi.org,
  files.pythonhosted.org, registry.npmjs.org, deb.debian.org, security.debian.org).
  Extend per ticket if a stack needs more.

## 4. Explicitly NOT doing

- `launch.sh` — unchanged (contract verified: lines 120, 135 call `"$SANDBOX" "$PY" "$STANOK_PY" run ...`).
- `scripts/run.sh` for darkcast — the Node implementation stays as-is (project-owned; new CLAUDE.md:
  "If `scripts/run.sh` already exists: use it as-is").
- No file placement, no commits, no docker build until the §2 decisions are confirmed.
