# PLAN — architectural review fixes (2026-09-19)

Input: external review of the machine zone (bash vs Python, Claude Code 2.1.88
compatibility) + `specs/HANDOFF-ARCH-REVIEW.md`. Every review claim below was
re-verified against the code at HEAD and against the real host CLI
(`/home/hermes/git/claude-code-2.1.88/cli.js`, `version: "2.1.88"`) and SDK
0.2.139 in `stanok/.venv`.

## Verification verdict

| Item | Verdict | Evidence |
|---|---|---|
| D1 (jq missing) | **CONFIRMED, severity raised** | `jq` used only in `hooks/verifier.sh:22,41`; Dockerfile apt list (lines 69-79) has no jq. Without jq the hook exits 0 silently (`FP` empty) — the RED CONFIRMED feedback is **dead in the Docker era**. The "operator-verified from trace" red phase in STATUS.md was verified in the bwrap era, before the Docker refactor. This is a silent functional regression, not just a missing dep. |
| D2 (bundled CLI in wheel) | **CONFIRMED** | `stanok/.venv/.../claude_agent_sdk/` is 311 MB and contains `_bundled/claude`. Dockerfile:11-19 ("does NOT bake in claude-code") is contradicted by Dockerfile:82. |
| D3 (inert deny entries) | **CONFIRMED against real 2.1.88** (reviewer could not — 2.1.88 not on npm; host has the source checkout) | `"ScheduleWakeup"`, `"Workflow"`, `"ReportFindings"`: 0 exact quoted hits in cli.js 2.1.88 (the 20 `Workflow` substrings are Bedrock API type names `AutomatedReasoningPolicyBuildWorkflow…`). `DISABLE_NON_ESSENTIAL_MODEL_CALLS`: 0 hits. All four are inert. Conversely confirmed PRESENT in 2.1.88: `dontAsk` (12), `enableWeakerNestedSandbox` (5), `failIfUnavailable` (5), `allowedDomains` (5), `append-system-prompt-file` (2), `hook_callback` (2), `--tools <tools...>` (1), `allowedTools` (60), `disallowedTools` (14). |
| R1 (in-process hook) | **FEASIBLE** | SDK 0.2.139: `ClaudeAgentOptions.hooks: dict[HookEvent, list[HookMatcher]]` (types.py:2064), `HookCallback` (types.py:599); cli.js 2.1.88 has `hook_callback`. **BUT contradicts the 2026-09-17 decision "NOT doing (final): in-process hooks" (STATUS.md) — owner decision required.** |
| R2 (bash→Python merge) | **CONFIRMED** | Flag duplication: `launch.sh:74-84` parses `--direct`/`--local-retries` and forwards them to argparse (`stanok.py:1101-1102`); marker written by bash (`launch.sh:127`), read by Python (`stanok.py:875,1010,1051,1125`); PID via env (`sandbox-run.sh:129` `STANOK_HOST_PID`); Python mock server as bash heredoc (`doctor.sh:114-128`). **Contradicts "NOT doing: sandbox-run.sh/launch.sh changes" — owner decision required.** |
| R3 (`--tools` instead of deny) | **FEASIBLE, refined** | SDK maps `tools`→`--tools` (subprocess_cli.py:586-591), `allowed_tools`→`--allowedTools` (:598), `disallowed_tools`→`--disallowedTools` (:607). `stanok.py:550` already passes `allowed_tools=CURATED_TOOLS`. The change is ADDING `tools=CURATED_TOOLS`, not replacing `allowed_tools`; then the 24 bare deny names can be dropped, keeping only the 10 path rules (`Read(.git/**)` … `Edit(evidence/**)`). `--tools` confirmed present in 2.1.88. |
| R4 (CLI delivery) | **OWNER'S CHOICE** | 2.1.88 is not on npm (404), so `npm i` in the Dockerfile is impossible; `COPY` of the 2.1.88 dir + node is the only bake-in option. Removes symlink walk (`sandbox-run.sh:41-58`), node file-mount (:70-77), PATH fix (:119-121). Cost: image rebuild per CLI change. |
| R5 (doctor→Python tests) | **FEASIBLE, refined** | Harness tests must NOT live in `tests/` (machine-owned; contract_lock snapshots it, verify_gate runs `run.sh list` on it). Separate dir, e.g. `launcher/tests_harness/`. |
| Line counts | **MATCH** | bash 729 (208+169+138+98+61+44+11), Python 1182, P0-launch.sh 191. |
| SDK 0.2.139 ↔ CLI 2.1.87/2.1.88 flags | **CONFIRMED** | `--include-hook-events` (subprocess_cli.py:688), `--session-mirror` (:714), `--thinking-display` (:761) are added only for options `stanok.py` never sets (`include_hook_events`, `session_store`, `thinking` — none in `ClaudeAgentOptions(...)` at stanok.py:544-554). |

## Corrections / additions to the review

1. **D1 is the top-priority finding.** It silently disabled the TDD red-phase
   feedback (the "RED CONFIRMED" acceptance criterion from STATUS.md is
   currently unverifiable in the Docker era). Fix is either one apt word or R1.
2. **D2 nuance:** `pip install --no-binary` builds from sdist (not "a 138 KB
   wheel"). Safe because `cli_path` is always set (stanok.py:44,545); if the
   host `claude` is missing the SDK falls back to the bundled CLI — with
   `--no-binary` that fallback disappears, i.e. launch fails closed. Acceptable
   (house style), but note it.
3. **R1 and R2 reverse explicit 2026-09-17 "NOT doing (final)" decisions**
   (STATUS.md). The review does not mention this; owner must decide explicitly.
4. **R3 refinement:** `allowed_tools` and `tools` are different SDK params
   (different CLI flags); both can coexist. Deny list shrinks 24+10 → 10.
5. **R5 refinement:** harness test dir must be separate from `tests/`.
6. **Not in the review:** `P0-launch.sh` (191 lines) is supervisor-side infra
   (role injection via `--append-system-prompt-file`), outside the machine zone;
   it is read in full and unaffected by R1-R5.

## Plan

All harness changes are made by the supervisor (machine cannot write
`launcher/`, `hooks/`, `Dockerfile` — ro mount + deny rules), each phase
verified by `doctor.sh` green + one real ticket run (rc=0, verifier=PASS).
If the owner prefers machine-side implementation, a phase becomes a ticket —
but the machine's writable zone (src/tests/docs/scripts) does not cover these
files, so that is not possible for phases 1-3.

### Phase 0 — owner decisions (no code)
- D-A: adopt R1 (in-process hook) or keep shell hook + add jq? (reverses
  "NOT doing: in-process hooks")
- D-B: adopt R2 (merge launch.sh/sandbox-run.sh/setup.sh into Python)?
  (reverses "NOT doing: launch.sh/sandbox-run.sh changes")
- D-C: R4 — keep host bind-mount or COPY CLI+node into the image?
- D-D: confirm phase order and go/no-go per phase.

### Phase 1 — defects (small, independent, no architectural risk)
- **P1.1 (D1):** add `jq` to Dockerfile apt list — UNLESS D-A=R1, in which
  case R1 removes the jq need entirely and P1.1 is skipped.
  Acceptance: `docker run --rm stanok-machine:latest sh -c 'command -v jq'`
  prints a path; one run shows `RED CONFIRMED` in the session stream after a
  Write to `tests/`.
- **P1.2 (D2):** `pip install --no-binary claude-agent-sdk` in Dockerfile;
  rewrite the Dockerfile:11-19 header comment to state the truth (wheel
  previously bundled a second CLI; now sdist-only, `cli_path` always the host
  binary, fail-closed without it).
  Acceptance: image shrinks by ~300 MB; doctor green; one run rc=0.
- **P1.3 (D3):** delete inert deny entries `ScheduleWakeup`, `Workflow`,
  `ReportFindings` and env `DISABLE_NON_ESSENTIAL_MODEL_CALLS` from
  `settings.stanok.json`.
  Acceptance: doctor green; one run rc=0, verifier=PASS, no denials in trace.

### Phase 2 — tool surface + hooks (R3 then R1, per D-A)
- **P2.1 (R3):** add `tools=CURATED_TOOLS` to `ClaudeAgentOptions`
  (stanok.py:544); shrink `deny` to the 10 path rules only.
  Acceptance: init tools = exactly [Read, Write, Edit, Grep, Glob, Bash];
  one run rc=0, verifier=PASS, 0 denials.
- **P2.2 (R1, if D-A=R1):** in-process `PostToolUse` hook in `stanok.py`
  (`hooks={"PostToolUse": [HookMatcher(...)]}`), callback runs
  `scripts/run.sh test <rel>` via `asyncio.create_subprocess_exec` (sync
  subprocess would block the event loop running the turn watchdog); delete
  `hooks/verifier.sh`, the `hooks` block in settings, the jq dependency, and
  the corresponding doctor check.
  Acceptance: one run shows `RED CONFIRMED` injected after a Write to
  `tests/` (session stream); no bash hook process in the trace; doctor green.

### Phase 3 — large refactors (per D-B, D-C)
- **P3.1 (R2, if D-B=yes):** merge `launch.sh` + `sandbox-run.sh` + `setup.sh`
  (390 lines) into one Python module (e.g. `launcher/host.py`); marker
  protocol becomes internal (no bash-written `.running`); reaper trap →
  `try/finally` + existing `_install_signal_handlers` (stanok.py:751);
  `status`/`stop`/`check-dirty` unchanged as CLI surface.
  Acceptance: doctor green (updated); sync + background + status + stop all
  work; rc codes 15/20/21/22/24 unchanged.
- **P3.2 (R4, per D-C):** if COPY — bake 2.1.88 + node into the image, delete
  symlink walk (sandbox-run.sh:41-58), node file-mount (:70-77), PATH fix
  (:119-121); if bind-mount — no change, document the decision in Dockerfile.
  Acceptance: doctor green; one run rc=0.
- **P3.3 (R5):** move `doctor.sh` checks into Python tests in
  `launcher/tests_harness/` (NOT `tests/` — machine-owned, contract_lock);
  add the jq check (if P1.1 applied) and the gate-order regression cases.
  Acceptance: same coverage as the 13 current checks, run under pytest;
  `doctor.sh` becomes a thin wrapper or is deleted (supervisor runbook
  updated).

### Phase 4 — stack-coupling workstream (orthogonal, from HANDOFF-ARCH-REVIEW)
The review's "P1–P9 (stack manifest, fail-closed `list`, `run.sh` protection)"
remain in force and are a SEPARATE workstream: they change `scripts/run.sh`
semantics and the ticket contract, not the bash/Python split. Sequenced after
phases 1-3, driven by the owner's answers to the 7 open questions in
`specs/HANDOFF-ARCH-REVIEW.md` §5.

## Explicitly NOT doing
- No changes to `stanok/src|tests|docs` (machine zone).
- No `CLAUDE.md` in the project root.
- No changes to the supervisor contract (stop conditions, rc table, summary.json
  schema) unless a phase's acceptance criterion requires it — none do.
- No model-server or Opik changes.
