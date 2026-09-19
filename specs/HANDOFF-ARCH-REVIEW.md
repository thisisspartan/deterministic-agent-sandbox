# HANDOFF — Architectural Review of the Stanok Machine

Date: 2026-09-19. Author: L1 Supervisor (control room).
Purpose: hand the project to an external architectural review. The review's
stated concern: **the development stack (currently Node.js + Python) is
patched into harness code by hand** (e.g. `scripts/run.sh` usage/dispatch),
so a stack change means hunting for and patching every coupling site.
This document maps the system, inventories every stack-coupling site, and
gives a change-impact matrix so the review can judge whether the seams are
in the right places.

All facts below were verified by reading the files at the cited lines on
2026-09-19 (stanok HEAD `c5d5fdc`). No code was modified for this handoff.

---

## 1. What the system is

A two-zone autonomous pipeline:

- **Control room** (this repo root): `CLAUDE.supervisor.md` (L1 role,
  injected via `--append-system-prompt-file` by `P0-launch.sh:187-191`),
  `CONTEXT.md` (persistent facts), `specs/` (specs + STATUS), `tickets/`
  (self-contained task tickets), `P0-launch.sh` (interactive supervisor
  launcher → local llama-server).
- **Machine zone** (`stanok/`, git submodule): the autonomous worker.
  The machine (a Claude Code session driven by `launcher/stanok.py` via
  `claude-agent-sdk`) reads ONE ticket, writes code in `src/tests/docs/
  scripts`, and is verified by an external gate. It never commits
  (`.git` is mounted read-only in the container); the operator commits
  afterwards, gated by `hooks/commit-msg` (TASK-ID required).

Roles are separated by file, not by auto-load: the root role file is
deliberately named `CLAUDE.supervisor.md` (a root `CLAUDE.md` would be
auto-loaded into the machine session — role leak, guarded by rc=24,
`stanok.py:1156-1158`).

## 2. Component map (machine zone)

| File | Lines | Responsibility |
|---|---|---|
| `launch.sh` | 138 | Host shim: arg parsing, `check-dirty` gate (rc=22, line 107), background nohup + marker (112-131), sync exec. Chooses sandbox vs bare python (`STANOK_NO_SANDBOX`). |
| `sandbox-run.sh` | 208 | Docker boundary: read-only repo mount + rw carve-outs (`src/tests/docs/scripts/evidence`, lines 93-104), host `claude` bind-mount via symlink-chain walk (55-68), host `node` file-mount (70-78), resource limits (141-145), cap-drop=ALL + seccomp/apparmor unconfined for nested bwrap (154-160), `--network=host` (197-208), reaper trap (169-172), venv→image-python remap (191-196). |
| `launcher/stanok.py` | 1182 | The runner: gates, ticket parse, quarantine, SDK session loop, turn watchdog, verify gate, contract lock, telemetry, summary.json, status/stop. |
| `scripts/run.sh` | 98 | **The project's test entrypoint** — the single canonical interface (`list`/`test`/`smoke`) used by the model, the hook, and the external verifier alike (D3). |
| `hooks/verifier.sh` | 61 | PostToolUse(Write\|Edit) hook: after a write under `tests/`, runs that test via `run.sh` and injects "RED CONFIRMED" context (line 49, 59-60). |
| `hooks/doctor.sh` | 169 | Operator pre-flight: 13 structural + gate-order checks, including live mock-server runs (rc=15/20/22/24 regression tests). |
| `hooks/commit-msg` | 11 | Operator-side git gate: commit message must contain `TASK-STANOK-CC-NNN`. |
| `.claude/settings.stanok.json` | 100 | Static machine config: env (timeouts, tracing→Opik, compaction window), tool allow/deny, native sandbox (bwrap) + network allowedDomains, the single hook registration. |
| `Dockerfile` | 104 | Machine image: debian-slim + git/curl/build-essential/python3 + bubblewrap + socat + pinned `claude-agent-sdk==0.2.139`; non-root user; no ENTRYPOINT. |
| `CLAUDE.md` (in stanok/) | 82 | Machine role: hard rules (4 writable dirs, no git writes, match existing stack), the `run.sh` contract, TDD discipline, ≤5-line final report. |
| `setup.sh` / `requirements.txt` | 44 / 3 | Host venv + commit-msg symlink + image build; sole dep `claude-agent-sdk`. |

### Control flow (one run)

```
launch.sh run <ticket> <label> [--background]
  └─ check-dirty (rc=22)                          [launch.sh:107]
  └─ sandbox-run.sh → docker run (ro repo, rw carve-outs)
       └─ python3 launcher/stanok.py run <ticket> -- <label>
            ├─ label guard (rc=15)                [stanok.py:1150]
            ├─ role-leak parent CLAUDE.md (rc=24) [stanok.py:1156]
            ├─ ticket exists (rc=13)              [stanok.py:1161]
            ├─ dirty tree (rc=22)                 [stanok.py:1164]
            ├─ flock single-run lock (rc=21)      [stanok.py:1169-1174]
            ├─ ticket header parse: impl:/test:/docs:/reset:none (rc=13)
            │                                [stanok.py:241-270, 909-931]
            ├─ preflight /props n_ctx (rc=20)     [stanok.py:182-206]
            ├─ quarantine declared paths → /tmp  [stanok.py:273-301]
            ├─ Opik trace baseline               [stanok.py:209-226]
            ├─ SDK session, turns 1..1+retries    [stanok.py:538-745]
            │    ├─ turn watchdog: shield+wait_for, TURN_TIMEOUT_S=1800
            │    ├─ API-error stop (is_error)     [stanok.py:518-526, 661-667]
            │    ├─ contract_lock: tests/ sha256 manifest per turn
            │    │                                [stanok.py:399-432]
            │    ├─ verify_gate: declared paths exist + run.sh list +
            │    │   run.sh test each (parallel)  [stanok.py:364-396]
            │    ├─ NO-OP assert: turn1 + 0 writes + pass → rc=1
            │    │                                [stanok.py:696-702]
            │    └─ FAIL → adaptive <contract_lock> fix prompt
            │                                  [stanok.py:711-739]
            ├─ Opik trace delta                  [stanok.py:976-993]
            └─ summary.json (the L1 contract)    [stanok.py:779-840]
```

### Contracts (the seams that matter)

1. **Ticket → machine**: header lines `impl: <path>` / `test: <path>` /
   `docs: <path>` / `reset: none` (`stanok.py:241-270`). Paths must be
   relative, no `..`, top-level dir in `src|tests|docs|scripts`
   (`_DECLARED_ZONES`, `stanok.py:65`).
2. **Machine → control room**: `evidence/<label>/summary.json`
   (`build_summary`, `stanok.py:779-840`): `rc`, `verifier`,
   `probe_result` (CLEAN-FIRST / PASS-AFTER-LOCAL-TRY / NO-OP-PASS /
   VERIFY-FAIL / EARLY-ABORT), `review_verdict` (CLEAN/DEFECT/NOOP),
   `turns`, tokens + cache_hit_rate, `contract_lock_violations`,
   `errors`, `failures`, `commit_sha`, `opik_traces`.
   Verdict rule for L1: SUCCESS iff `rc==0 AND verifier=="PASS"`;
   NO-OP iff `probe_result=="NO-OP-PASS"` (rc=1 by design — rc=1 is
   polysemous, disambiguated by probe_result, `stanok.py:786-797`).
3. **Project → verifier (D3)**: `scripts/run.sh {list|test <path>|smoke
   <path>}`. The runner (`stanok.py:344-361, 379-396`), the hook
   (`verifier.sh:49`), and the model's Bash all invoke this ONE script —
   no component hardcodes a test runner invocation.
4. **Static config**: `.claude/settings.stanok.json` (loaded natively by
   the CLI); runtime-only keys (endpoint/model/timeouts) come from
   `build_agent_env()` (`stanok.py:438-461`) — the split is deliberate
   ("Prefix Invariance": settings.env would silently override SDK env).
5. **Env knobs**: `STANOK_*` (`SERVER_URL`, `MODEL`, `LOG_DIR`,
   `TURN_TIMEOUT_S`, `API_TIMEOUT_S`, `LOCAL_RETRIES`, `DOCKER_IMAGE`,
   `CONTAINER_MEM/PIDS/CPUS`, `SKIP_SERVER_CHECK`, `SKIP_OPIK_CHECK`,
   `NO_SANDBOX`, `HOST_PID`, `CLAUDE_BIN`, `REQUIRED_WINDOW`,
   `CONTEXT_ROT_TOKENS`).

### rc code table

| rc | meaning | site |
|---|---|---|
| 0 | success (verifier PASS) | `run_continuous_session` |
| 1 | generic failure / retries exhausted / NO-OP-PASS / turn timeout / API error | `stanok.py:600-603, 661-667, 696-702, 743-745` |
| 13 | ticket missing / header invalid / no declared paths | `stanok.py:913-931, 1161` |
| 14 | workspace prep error | `stanok.py:944-951` |
| 15 | invalid label | `stanok.py:1150` |
| 20 | server unavailable / n_ctx too small | `stanok.py:935-942` |
| 21 | lock held (another run) | `stanok.py:1169-1174` |
| 22 | dirty tree | `launch.sh:107`, `stanok.py:1164` |
| 24 | role leak (parent CLAUDE.md) | `stanok.py:1156-1158` |
| 128+sig | interrupted | `stanok.py:751-765` |

## 3. Stack-coupling inventory (the review's core question)

**Design intent (stated in the code):** the harness is stack-agnostic;
`scripts/run.sh` is the single stack seam ("stanok itself no longer knows
or cares what language backs `scripts/run.sh`" — `sandbox-run.sh:20-23`);
the Dockerfile adds a toolchain "one apt-get/curl line the day a real
ticket actually needs it" (`Dockerfile:23-25`); the machine is instructed
to "match the project's EXISTING stack" (`CLAUDE.md:28-30`).

**Reality — every place a stack change touches:**

| # | Site | What is coupled | Severity |
|---|---|---|---|
| 1 | `scripts/run.sh:16-19` | usage text names `*.test.js` / `*_test.py` / `src/*.js` / `src/*.py` | cosmetic but operator-facing |
| 2 | `scripts/run.sh:49-52` | test-path regexes: `\.test\.js$` and `_test\.py$` (naming conventions of two stacks) | **hard gate** — a new stack's test files are refused (rc=2) by runner, hook, and verifier alike |
| 3 | `scripts/run.sh:63-74` | dispatch: `node --test --test-force-exit` vs `python3` | **hard** — the actual runner invocation |
| 4 | `scripts/run.sh:80-89` | smoke: `src/*.js`→node, `src/*.py`→python3, 10s timeout | hard |
| 5 | `scripts/run.sh:91-94` | `list`: `find tests -name '*.test.js'` + `'*_test.py'` | hard — discovery |
| 6 | `Dockerfile:69-79` | baked toolchain: python3/pip/venv + build-essential; NO node | medium — new stack = apt line (documented as intended) |
| 7 | `sandbox-run.sh:70-78` | **node is bind-mounted from the HOST** at `/usr/local/bin/node` (host version = container version); python comes from the image | **asymmetry**: two stacks, two different version-pinning strategies |
| 8 | `settings.stanok.json:80-91` | sandbox `allowedDomains`: pypi.org, files.pythonhosted.org, registry.npmjs.org, debian repos | medium — new stack's registries must be added or `pip/npm/apt install` in-container fails |
| 9 | `stanok.py:307-341` (`_extract_smart_diff`) | error-compression heuristics: high-priority regex is JS/TAP-flavored (`strictequal`, `deepstrictequal`, `not ok N`, `# fail N`); Python tracebacks only match the low-priority `assert|error:` tier | low — degrades fix-prompt quality, not correctness |
| 10 | `stanok.py:42` | default model name `Qwen3.8-27B-MTP` (also `P0-launch.sh:42`) | low — env-overridable, duplicated in two files |
| 11 | `stanok.py:218` | Opik URL `http://localhost:8080/...project_name=stanok` **hardcoded, no env override** (unlike SERVER_URL) | low-medium — portability wart |
| 12 | `stanok.py:827` | `cloud_calls: 0` constant in summary.json | vestigial field |
| 13 | `CLAUDE.md:12-15, 28-30, 46-51` | machine role names the 4 dirs and the run.sh contract; explicitly stack-neutral ("whatever language this project already uses") | none — this is the seam working as designed |
| 14 | `hooks/verifier.sh`, `hooks/doctor.sh`, `hooks/commit-msg`, `launch.sh`, `stanok.py` gates | all stack-neutral (they delegate to run.sh / check structure) | none |

**Key structural fact:** `run.sh` is simultaneously (a) a harness contract
with a fixed 3-subcommand CLI, (b) a *project artifact* that the machine
is allowed to bootstrap when absent (`CLAUDE.md:46-51`), and (c) currently
a hand-maintained dual-stack (js+py) dispatcher with regexes. The
harness itself (`stanok.py`) contains **zero** language-specific logic
beyond the smart-diff heuristics (#9). So the user's complaint is
precisely located: the stack knowledge lives in ONE file, `run.sh` — but
that file is a free-form shell script, so "change the stack" = "edit
regexes and dispatch by hand, and remember the Dockerfile line and the
allowedDomains".

## 4. Change-impact matrix (what a stack change actually touches)

**A. Add a stack (e.g. Go) alongside js+py:**
`run.sh` (regex + dispatch + list) · `Dockerfile` (apt line) ·
`settings.stanok.json` (allowedDomains if new registries) ·
`stanok.py` (optionally smart-diff patterns) · nothing else.

**B. Replace the stack (drop JS, keep Python only):**
`run.sh` (delete js branches) · `settings.stanok.json` (npm domain
optional) · `sandbox-run.sh` node mount becomes dead weight (harmless) ·
`src/tests` rewritten per ticket by the machine · nothing else.

**C. Swap test framework within a stack (node --test → jest / pytest → unittest):**
`run.sh` dispatch line only. (This is the D3 seam working as intended.)

**D. Change the model / server:**
env only (`STANOK_SERVER_URL`, `STANOK_MODEL`) — no code edit.

The matrix shows the seam design is *mostly* sound: the harness is
stack-agnostic and the stack knowledge is concentrated. The review
questions are about the **shape** of that concentration, not its
location.

## 5. Open questions for the review (observations, not prescriptions)

1. **Ownership of `run.sh`.** It is the only stack-coupled file, but it is
   free-form shell with per-stack regexes. Options the review may weigh:
   keep it minimal and per-project (machine bootstraps it per stack,
   harness never edits it); or make it config-driven (a dispatch table /
   manifest, e.g. `tests/` layout + runner per extension); or move
   discovery out of `run.sh list` into a project manifest the harness
   reads. Note the constraint: `run.sh` is writable by the machine
   (rw carve-out) but contract_lock + CLAUDE.md forbid editing it to
   make failures disappear — any redesign must preserve that invariant.
2. **Node asymmetry (#7).** node = host bind-mount (version drift with
   the host), python = image-baked. Two pinning strategies for two
   stacks. Is host-mounting the right call for node, or should the
   image own both (at the cost of the "bind-mount, don't reinstall"
   anti-drift decision documented in `Dockerfile:11-19` — which was
   specifically about the *claude CLI*, not node)?
3. **Smart-diff heuristics (#9).** JS/TAP-flavored; a Python or Go
   failure gets only the low-priority compression tier. Should the
   patterns be per-stack, or should the fix-prompt carry the raw tail
   regardless?
4. **Hardcoded Opik endpoint (#11)** and duplicated model default (#10):
   trivial env-override gaps, listed for completeness.
5. **rc=1 polysemy** (`stanok.py:786-797`): NO-OP vs exhausted-retries vs
   timeout vs API error all share rc=1, disambiguated by
   `probe_result`/`error` fields. Deliberate (documented), but a review
   may question whether the L1 contract should carry distinct codes.
6. **doctor.sh runs real launches** against mock servers
   (`doctor.sh:59-166`) — heavy for a "doctor", but it is the only
   regression test of the gate order. There is no other test suite in
   the machine zone.
7. **Single-slot inference server** shapes the whole protocol (one run
   at a time via flock; the supervisor's no-polling blocking wait exists
   because a second concurrent session evicts the KV cache). Any
   parallelism proposal must start from this constraint.

## 6. Current state facts (for the reviewer's orientation)

- Batch of tickets complete: SMOKE-01, SMOKE-02, CC-077 (Docker
  refactor), CC-078 (Node.js terminal fire), CC-079 (Python multicolored
  fire). See `specs/STATUS.md`.
- **Uncommitted machine artifacts** (machine cannot commit; operator
  must): `src/fire_color.py`, `tests/fire_color_test.py`,
  `docs/fire_color.md` (CC-079 deliverables, untracked at HEAD `c5d5fdc`).
- `doctor.sh` last verified: 13 ok, 0 fail.
- Model server: remote `http://192.168.8.131:8080` (Qwen3.8-27B-MTP),
  known-flaky (mid-run "API Error: terminated" / "503 Loading model");
  the launcher now stops on `is_error` instead of burning retries
  (`stanok.py:518-526, 661-667`).
- Tracing: self-hosted Opik (localhost:5173 UI / :8080 API), OTLP from
  the machine via `settings.stanok.json:21-24`; per-run trace delta in
  `summary.json.opik_traces`.
- History of the boundary: bwrap + bash-gate + read-guard + custom `run`
  MCP tool (waves 1-3) → Docker container + native Bash (current). The
  bwrap→Docker swap was done as a pure boundary-implementation change
  with the same calling contract (`sandbox-run.sh:4-11`) — a precedent
  for how boundary changes are expected to be made here.
- Persistent decisions and their rationale: `CONTEXT.md` (669 lines) and
  `specs/SPEC-STANOK-HARNESS-REVIEW.md` (wave plan; worktree REJECTED,
  ticket-scoped invariant chosen instead).

## 7. Ground rules for anyone modifying the machine zone

- The machine (ticket-driven session) may write ONLY `src/ tests/
  docs/ scripts/`; everything else is ro-mounted. `.git` is ro — no
  commits from inside.
- `verify_gate` on the host side is authoritative; the container's own
  test runs are advisory feedback only.
- Fail-closed is the house style: unknown state → refuse (see
  `dirty_tree_gate`, preflight, `_validate_declared_path`).
- New outcome = one row in `_status_fields` + one `summary.json` field;
  do not introduce parallel verdict channels.
- `doctor.sh` must stay green (13 ok, 0 fail) after any harness change.
