# SPEC — Sandbox & Docker improvements, 2026-09-18 (chronological)

Scope: the B1-hybrid Docker refactor of the stanok machine (bwrap → container
boundary) plus the same-day follow-up wave. Source of truth for the design:
`specs/PLAN-DOCKER-REFACTOR.md` (COMPLETE). This spec lists what was actually
done, in order, with commits and verification evidence.

## Architecture result (B1 hybrid)

- **Outer boundary — Docker container**: repo mounted read-only with writable
  carve-outs (`src/`, `tests/`, `docs/`, `scripts/`, `evidence/`); `.git`
  read-only; host claude/node bind-mounted; `cap-drop=ALL`,
  `no-new-privileges`, non-root `--user`, limits mem=4g / pids=512 / cpus=2;
  `seccomp=unconfined` + `apparmor=unconfined` (required for nested bwrap).
- **Inner boundary — claude-code native sandbox**: bwrap per Bash command,
  `sandbox.enabled: true`, `failIfUnavailable: true`,
  `enableWeakerNestedSandbox: true`, network restricted to `allowedDomains`.
- **Tools**: native UNRESTRICTED Bash replaces the MCP `run` tool; the fixed
  test contract is `scripts/run.sh {list,test,smoke}`.
- **Ticket format**: literal header lines `impl:` / `test:` / `docs:` +
  optional `reset: none` (replaces derived `module:` paths), fail-closed
  validation (relative, no `..`, top-level dir in src/tests/docs/scripts →
  else rc=13).

## 1. Core refactor — steps 1–9 (stanok `9422048`)

1. **`Dockerfile` (new)** — debian:bookworm-slim + git/curl/build-essential/
   python3/pip + `claude-agent-sdk==0.2.139` + **bubblewrap + socat** (native
   sandbox deps), user `stanok` (10001), no ENTRYPOINT.
2. **`sandbox-run.sh` (replaced the bwrap version, same calling contract)** —
   fixes verified against the host before placement:
   - parent repo ro-mounted → ticket resolution + rc=24 role-leak gate live;
   - `compgen -v` (was `-e`) → `STANOK_*` env vars actually pass;
   - node file-mounted `/usr/bin/node → /usr/local/bin/node:ro` (a directory
     mount of `/usr/bin` would have hidden the image python);
   - container PATH extended (node + claude shim dir);
   - claude mount scope = shim dir + resolved cli.js dir ONLY (the old
     `dirname` logic leaked `/home/hermes/git` incl. `.env` keys to the model);
   - multi-hop claude symlink chain fully mounted (intermediate hop dangled);
   - host venv python remapped to the image python 3.11 (SDK baked in image;
     host 3.12 site-packages are incompatible read-only);
   - tmpfs HOME (ephemeral, no host coupling);
   - `STANOK_HOST_PID` passed → host-side `launch.sh status` works;
   - `exec` dropped → the reaper trap actually fires (container cleanup on stop).
3. **`CLAUDE.md` (machine role, replaced)** — four writable dirs, native
   unrestricted Bash, `scripts/run.sh` contract, stack-neutral prose.
4. **`.claude/settings.stanok.json`** — `Bash` allowed, `mcp__run__run`
   removed, native sandbox ON with `enableWeakerNestedSandbox` +
   `allowedDomains` (B1 hybrid; the initial "bwrap impossible in container"
   claim was disproven empirically — see plan §5 matrix).
5. **`launcher/stanok.py` patch** (supervisor-applied, user-authorized;
   stanok `4faa1b2`, gitlink `42ad73f`):
   - `CURATED_TOOLS` → `["Read","Write","Edit","Glob","Grep","Bash"]`;
   - `_build_run_mcp_server()` deleted (52 lines), `mcp_servers` dropped;
   - new literal `impl:/test:/docs:` header parser + fail-closed path
     validation (protects quarantine `shutil.move` from arbitrary host paths);
   - `prepare_workspace` covers `scripts/`;
   - retry prompt stack-neutral.
6. **Image build** — `docker build -t stanok-machine:latest`.
7. **Static container checks** (real script, no model): id, python3, node,
   claude discoverability, rw in `src/`, EROFS on `.git`, parent `tickets/`
   and parent `CLAUDE.md` visible.
8. **NO-OP pipeline smoke** `smoke02-docker3` — probe_result=NO-OP-PASS,
   verifier=PASS, 1 turn, 0 writes, no orphan containers.

## 2. Rebuild smoke — step 10 (label `rebuild01`)

9. **`rebuild01`** (ticket CC-077, new format) — first honest run on the
   Docker boundary: rc=0, verifier=PASS, CLEAN-FIRST, 1 turn 67s, cache
   83.0%, writes=3 (quarantine moved the 3 pre-existing artifacts, machine
   rebuilt them via TDD), no orphan containers. Deliverables committed
   (stanok `51ebcd2`).

## 3. Follow-up wave — step 11 (stanok `4881cda`, gitlink `35bea4b`)

10. **`hooks/doctor.sh`** — Docker checks added (`docker available`,
    `machine image built`), placeholder tickets moved to the new header
    format, bwrap prose removed → **15 ok, 0 fail** (was 13 checks).
11. **`setup.sh`** — builds the machine image (`.venv` + SDK + docker build).
12. **`scripts/run.sh`** — header now states the fixed contract (native Bash,
    single canonical test invocation).
13. **`launch.sh`** — stale "bwrap sandbox" comment → "container".
14. **`stanok/README.md`** — Docker boundary throughout: requirements
    (Docker, no host bubblewrap), setup, structure (+Dockerfile,
    sandbox-run.sh), env table (+`STANOK_DOCKER_IMAGE`,
    `STANOK_CONTAINER_MEM/PIDS/CPUS`), gate order, how-it-works, commits.
15. **Root `README.md`** — quickstart step 1 (setup.sh → .venv + SDK + Docker
    image; doctor 15 ok).
16. **Re-verification** `rebuild02` (CC-077) — rc=0, verifier=PASS,
    CLEAN-FIRST, 1 turn 72s, cache 92.3%, errors=[]. Deliverables committed
    (stanok `4484c40`, gitlink `885ecc6`).
17. **skeleton-pub sync** — 10 files (Dockerfile + 9 modified infra files);
    submodule `d46b581`, root `202b65a`, both pushed to GitHub.

## 4. Post-wave verification (Opik pipeline)

18. **`rebuild03`** (CC-077) — rc=0, verifier=PASS, CLEAN-FIRST, 1 turn 51s,
    cache 93.0%; traces confirmed in Opik: 21 spans (9 llm_request, 9 tool,
    3 hook), project `stanok`. Deliverables committed (stanok `3421328`,
    gitlink `a187b98`).

## Related same-day infra fix (not sandbox/docker)

- **Opik auto-start** (opik repo `f68e404`): `restart: unless-stopped` on all
  12 long-running compose services (one-shot inits excluded — they loop and
  block `clickhouse`); docker daemon is boot-enabled → the stack survives
  reboots. Verified: PID-1 kill → auto-restart. Recorded in `CONTEXT.md`.

## Verification summary

| Run | Label | Result |
|---|---|---|
| NO-OP smoke | `smoke02-docker3` | NO-OP-PASS, PASS, 0 writes |
| Rebuild | `rebuild01` | rc=0, PASS, CLEAN-FIRST, 67s |
| Re-verify | `rebuild02` | rc=0, PASS, CLEAN-FIRST, 72s |
| Opik check | `rebuild03` | rc=0, PASS, CLEAN-FIRST, 51s, 21 spans in Opik |

Doctor: **15 ok, 0 fail**. No orphan containers in any run.
