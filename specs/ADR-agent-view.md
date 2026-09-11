# ADR-agent-view — replacing the manual supervisor with native Claude Code Agent View

Status: **PROPOSED / NO-GO as written** (see §6)
Date: 2026-09-11
Scope: review of the "Research Protocol: replace `stanok.py` run/status/stop/watch
with native Claude Code Agent View" draft, plus the cheap empirical checks that
could be run without touching the machine's pinned binary.

---

## 1. Why this ADR exists

The draft protocol proposed migrating the file-based supervisor
(`stanok/launch.sh` background detach + `.running` PID marker;
`stanok/launcher/stanok.py` `cmd_run` background branch, `cmd_status`, `cmd_stop`,
`cmd_watch`) to native Agent View primitives:

`claude --bg` / `claude agents` (roster) / `claude attach|logs|stop|rm|respawn`
with per-worktree isolation, per the protocol's F1–F6.

The protocol is a good *method* (empirical gates, Q5/Q2 prioritized, version-pinned
ADR). This ADR records what happens when its Phase 0 gate is applied to **this**
machine, and answers the three questions that do not need an upgrade.

## 2. Verified facts (this machine, 2026-09-11)

| # | Fact | How verified |
|---|------|--------------|
| V1 | Installed system claude = **2.1.88** | `claude --version` |
| V2 | 2.1.88 has **no** Agent View: subcommands are only `agents, auth, auto-mode, doctor, install, mcp, plugin, setup-token, update`; `agents` = "List configured agents" (subagent definitions, not a session roster) | `claude --help` |
| V3 | 2.1.88 bundle has no daemon surface: `--bg`=0, `cc-daemon`=0, `control.sock`=0, `supervisorPid`=0, `bg spawned`=0, `attach-journal`=0 (all grep counts = 0) | grep `/home/hermes/git/claude-code-2.1.88/cli.js` |
| V4 | `~/.claude/daemon/{roster.json,attach-journal/}` and `~/.claude/daemon.log` exist but are **stale artifacts of another build**: `daemon.log` records `version=2.1.221` with `[bg] bg spawned … (spare)/(slash)` and `/tmp/cc-daemon-1000/…/control.sock`, last active **2026-08-19**. `roster.json` = `{"proto":1,"workers":{}}`, dead `supervisorPid:180579`. That install was removed (tasks #207–#209). | `cat ~/.claude/daemon.log`, `roster.json` |
| V5 | A **2.1.233** claude binary with Agent View IS present on the machine, bundled inside the SDK venv: `stanok/.venv/.../claude_agent_sdk/_bundled/claude` (324 MB). `--version` → 2.1.233; `--help` shows `--bg, --background  Start the session as a background agent` and `agents  Manage background agents`. | run the bundled binary |
| V6 | The runner **deliberately pins** the self-patched 2.1.88: `stanok.py:401 cli_path=CLAUDE_BIN`, `CLAUDE_BIN = STANOK_CLAUDE_BIN or shutil.which("claude")` → the 2.1.88 binary. The SDK's bundled 2.1.233 is bypassed. | `stanok.py:44,401` |
| V7 | `--append-system-prompt-file` **is** a registered option in 2.1.88 (`--append-system-prompt-file <file>`), consistent with `P0-launch.sh` using it interactively → resolves the F6 doc ambiguity in our favour. | grep bundle |
| V8 | 2.1.88 native flags relevant to the questions: `--worktree`/`-w`, `--tmux`, `--brief`, `--input-format stream-json`, `--output-format json\|stream-json`, `--json-schema`. | `claude --help` |

## 3. The protocol's entry gate: NO-GO on this machine

The protocol requires claude ≥ 2.1.139 (F4). Installed = 2.1.88 (V1). Agent View
does not exist in the running binary (V2, V3). Therefore **Q1, Q3, Q4, Q6, Q7, Q8
cannot be executed on the machine** — there is no `--bg` to attach them to. Running
them against a scratch install (or against the SDK's bundled 2.1.233, V5) would
test a *different binary* than the machine runs; results would not transfer.

**Correction to the protocol:** add a step 0′ — reconcile *docs version* vs
*installed binary*, and compare against `STANOK_CLAUDE_BIN`. If pinned < required,
the protocol is not executable on the machine and must be split (see §6).

## 4. The three answerable questions

### Q2 — SDK ↔ Agent View parity: **FAIL (SDK has no `--bg`)**
Read `claude_agent_sdk==0.2.139` in the machine venv:
- Zero references to `--bg`, background agents, daemon, roster, respawn,
  `control.sock`. (The only "attach" hits are transcript message-type names
  `user/assistant/progress/system/attachment`, unrelated.)
- The transport (`_internal/transport/subprocess_cli.py`) builds only a headless
  process: `claude --output-format stream-json --verbose … --input-format stream-json`
  (line 783: *"Always use streaming mode with stdin"*).
- The SDK declares `__cli_version__ = "2.1.233"` but that only names the binary it
  *bundles*; it exposes no Agent View API.

**Consequence:** Agent View is a CLI-only feature. The Python runner cannot reach it
without shelling out to the `claude` binary directly.

### Q5 — programmatic retry-turn injection: **PASS, and it is what the SDK already does**
The SDK's own transport *always* uses `--input-format stream-json`: each
`client.query(prompt)` writes one user message
`{"type":"user","message":{"role":"user","content":...}}` to the live process stdin.
So the machine's retry-turn injection is **already implemented over the native
stream-json protocol** — it is not an SDK-specific hack. Proven directly on 2.1.88
(prototype (c), raw log in `stanok/evidence/agent-view-research/stream-json-prototype.log`):

```
claude -p --input-format stream-json --output-format stream-json --verbose \
       --model Qwen3.8-27B-MTP --settings {}          # cwd=/tmp/proto-empty
stdin: {"type":"control_request","request_id":"init-1","request":{"subtype":"initialize"}}
stdin: {"type":"user","message":{"role":"user","content":"Reply with exactly one word: ALPHA"}}
stdin: {"type":"user","message":{"role":"user","content":"Now reply with exactly one word: BETA"}}
```
Result: one process, two turns, both answered (`ALPHA`, `BETA`), **identical
session_id** (`096da95a-…`) across both results; system init reports
`claude_code_version":"2.1.88"`. → A retry-turn can be injected programmatically
into one live session on the **pinned 2.1.88**, with no daemon and no `--bg`.

### Q9 — role injection with `--bg`: **moot here; flag present for the current mode**
`--append-system-prompt-file` is registered in 2.1.88 (V7) and works in the current
interactive/supervisor usage (`P0-launch.sh`). The `--bg` half of Q9 is untestable
(no `--bg`). Fallback if ever needed: system prompt via SDK/settings
(`system_prompt` `type:"preset"` + `append`).

## 5. Native-2.1.88 primitives the protocol overlooked

| Native in 2.1.88 | Protocol question | Note |
|---|---|---|
| `--worktree`/`-w`, `--tmux` | Q7 | Native per-session worktree isolation exists **today**; the F3 substance is testable without an upgrade. |
| `-p --input-format stream-json --output-format stream-json` | Q5 | Verified working (see Q5). |
| `--output-format json`, `--json-schema` | Q6 | Structured result natively; still not an incremental `summary.json`, so a thin translation layer stays. |
| `--append-system-prompt-file` | Q9/F6 | Present (V7). |
| `--brief` (SendUserMessage tool) | Q5 | Unexplored; candidate for agent→user messaging. |

## 6. Decision

**NO-GO for the protocol as written on this machine.** Agent View is unavailable in
the pinned 2.1.88 binary (V2–V3). The migration is deferred behind an explicit
upstream decision.

Two tracks:

- **Track A (now, no upgrade):** validate the 2.1.88-native primitives — stream-json
  retry-injection (**done, PASS**), `--worktree` isolation (Q7), structured output
  (Q6). This is genuine "native first" and touches none of the self-patches.
- **Track B (deferred, gated on a "upgrade claude" decision):** Agent View proper.
  Requirements and costs, each of which is itself a decision:
  1. **Accept the patch cost.** The machine pins 2.1.88 *on purpose* (`cli_path`,
     V6) to carry the self-patches (think-marker `think_medium`, prompt section-6
     conservation, error-`tool_result` handling — tasks #234/#235/#241/#242).
     Upgrading abandons or forces a re-port of the patch set against a ~13 MB
     minified bundle. (The SDK already bundles 2.1.233, V5, so a test binary is
     available — but the patches are not in it.)
  2. **Research Preview.** F4: admin-disableable, may change between minors; keep
     the `launch.sh`/`stanok.py` fallback until several minors stabilize.
  3. **Evidence-model redesign.** F3's per-worktree parallelism collides with the
     machine's single-tenant model (`src/`, `tests/`, `docs/`, `evidence/` are
     shared paths; one-run lock rc=21). The protocol flags this in §Q7 as out of
     scope — i.e. even GO-full is **not** a drop-in for `stanok.py`.

## 7. Consequences

- `stanok.py`'s supervisor (`run`/`status`/`stop`/`watch`, PID `.running`, lock
  rc=21) stays as the transport until Track B is explicitly approved.
- No code changes are implied by this ADR.
- The cheap native wins (Track A) can be pursued independently and are the
  recommended next step.
- On any future claude upgrade, re-run this gate: `claude --version` must be
  ≥ the Agent View minimum, and `STANOK_CLAUDE_BIN` must resolve to that binary.

## 8. Risks / caveats

1. V5 means Agent View is *reachable today* by pointing at the SDK's bundled
   2.1.233 — but that binary lacks the 2.1.88 self-patches, so testing there
   measures a different machine than we ship.
2. The stale `~/.claude/daemon/` artifacts (V4) are easy to misread as evidence
   that the current binary supports Agent View. They are not; they are leftovers
   from a removed 2.1.221 install. (This is exactly the "stale session artifacts"
   class the protocol's Q8 warns about.)
3. Doc-vs-binary drift (F6/V7) argues for always resolving upstream feature claims
   against the bundle, not the docs page.

## 9. Reproduction

```bash
claude --version                                   # 2.1.88
claude --help                                      # no --bg; agents = subagents
grep -c -- '--bg' /home/hermes/git/claude-code-2.1.88/cli.js          # 0
cat ~/.claude/daemon.log                           # version=2.1.221, stale
stanok/.venv/lib/python3.12/site-packages/claude_agent_sdk/_bundled/claude --version  # 2.1.233
grep -rniE -- '--bg|daemon|roster|respawn|control.sock' \
  stanok/.venv/lib/python3.12/site-packages/claude_agent_sdk --include='*.py' | wc -l  # 0

# Q5 prototype (raw log: stanok/evidence/agent-view-research/stream-json-prototype.log)
PROTO_LOG=/home/hermes/darkcast/stanok/evidence/agent-view-research/stream-json-prototype.log \
  python3 /tmp/proto_stream_json.py
```
