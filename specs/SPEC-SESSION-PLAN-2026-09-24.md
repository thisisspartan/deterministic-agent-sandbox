# SPEC — SessionPlan: single source of policy (2026-09-24)

> **STATUS 2026-09-24: T2 CANCELED (burned).** The preflight gate (host probes,
> `oracle:`, rc=29/30) and the retirement of quarantine are **cancelled**; the
> plan file `PLAN-T2-PREFLIGHT-2026-09-24.md` is deleted. Rationale: REVIEW
> `specs/REVIEW-KISS-CLI-FIRST-2026-09-24.md` §9, ticket CC-131. CC-119 was
> closed by CC-125 (`edit:`) + the grill, not by a preflight. The T2 sections
> below are kept as a historical record only. **T1 shipped**; **T3–T5 deferred**
> (REVIEW §5). The `probe_specs` field was a T2 placeholder and has been removed
> from `SessionPlan`.

## Problem

The same file policy is currently spread across 6 independent mechanisms
(`launcher/stanok.py` + `launcher/sandbox.py`):

| # | Consumer | Current input |
|---|----------|---------------|
| 1 | `parse_ticket_header()` (stanok.py:462) | ticket header → `declared_paths` |
| 2 | `prepare_workspace()` (stanok.py:494) | `declared_paths` → quarantine |
| 3 | `_tests_manifest()` (stanok.py:690) | hardcoded `tests/**` + `scripts/run.sh` |
| 4 | `_pretooluse_lock_hook` + `_check_contract_lock` (stanok.py:720) | manifest + `declared_paths` (run.sh exemption) |
| 5 | `verify_gate()` (stanok.py:603) | `declared_paths` |
| 6 | `sandbox_argv()` (sandbox.py:54-63) | hardcoded rw zones `src/tests/docs/scripts/evidence` |

Consequences observed in production:
- CC-119 retry1: a ticket requiring an edit of an existing test was denied
  by the contract lock; the workaround (quarantine + recreate via
  `git show HEAD:`) had to be encoded in the ticket prose.
- CC-119 retry1: an infeasible numeric contract (max flame-body heat
  0.6938 < required 0.75) was discovered only after the agent burned a
  session (TURN-TIMEOUT).
- The mount policy (consumer 6) is disconnected from the ticket policy
  (consumers 1-5): the agent's Bash gets zone-level RW regardless of what
  the ticket declares.

## Architecture

### SessionPlan (single source of truth)

```python
@dataclass(frozen=True)
class SessionPlan:
    declared_paths:  tuple[str, ...]  # ticket header: impl:/test:/docs:/scripts:
    mutable_paths:   tuple[str, ...]  # always == declared_paths (edit: paths included, CC-125)
    protected_paths: tuple[str, ...]  # pre-existing manifest keys (tests/**, scripts/run.sh)
    rw_zones:       tuple[str, ...]  # ("src","tests","docs","scripts","evidence"); T4 would derive them
    git_mode:       str = "ro"        # .git is always RO (verified, see "Git" below)
```

Construction order in `main()`:
1. `parse_ticket_header()` →
   `plan = SessionPlan(declared, mutable=declared, protected=(),
   rw_zones=<current tuple>, git_mode="ro", edit_paths=<CC-125>)`
2. `prepare_workspace(plan)` (quarantine — T2 burned, so it stays)
3. `manifest = _tests_manifest()` →
   `plan = dataclasses.replace(plan, protected_paths=tuple(manifest.keys()))`

All 6 consumers take `plan` (or its fields). No consumer reads
declared_paths / manifest / zones from anywhere else.

### Preflight state machine (T2) — CANCELED 2026-09-24

```
NEW TICKET → PREFLIGHT (host-side probes, before container/agent)
  ├─ PROBE_FAIL        → rc=29, agent never starts
  ├─ ALREADY_SATISFIED → probe_result=NO-OP-PASS, no agent
  └─ NEEDS_WORK        → materialize → AGENT
```

- **NO-OP-PASS semantics (I3):** "all mandatory observable acceptance
  conditions of THIS ticket are already satisfied without any change" —
  NOT "all current repository tests are green". A probe evaluates the
  declared ticket contract (numeric bounds, rendering contract, CLI
  behavior), not the test suite as a whole. Otherwise a false PASS is
  merely moved from the agent to the supervisor.
- The existing W2.4 heuristic (turn 1, zero Write/Edit → NO-OP-PASS, rc=1,
  stanok.py:1238) stays as a backstop until T2; the preflight probe is the
  primary gate.
- **Quarantine is retired in T2, and only then.** Its real job (preventing
  a stale artifact from satisfying the ticket) is taken over by the
  ALREADY_SATISFIED gate. Until T2, quarantine stays as-is.

### Probes (decision A) — CANCELED 2026-09-24

- `probes/` — **supervisor zone** (repo root, next to `specs/`/`tickets/`):
  probe implementations, written by the supervisor together with the
  ticket. A probe runs on the host BEFORE container creation.
- Probe registry/parser — `launcher/` (harness code, supervisor-executed).
- Probe declaration — ticket header (`probe: <name>`).
- Structured JSON result; failure → **rc=29** (new code; 20/22/24/25/26/27/28
  are taken). rc=29 means "the agent never started" — distinct from
  1 (test failure), 6 (env failure), 124 (timeout).
- `probe_result` already exists in the summary.json contract
  (stanok.py:6, 1359); values: CLEAN-FIRST / PASS-AFTER-LOCAL-RETRY /
  NO-OP-PASS (existing) + preflight outcomes (T2).

### File enforcement (T3/T4)

- **T3** — host-side experiment (no agent), three cases:
  (a) repo:ro + existing file:rw bind (mount order, overlay behavior);
  (b) nonexistent declared file → nearest existing parent dir:rw
      (Docker creates a DIRECTORY for a nonexistent file source — a file
      bind is impossible, so this rule is a necessity, not a preference);
  (c) pytest + `__pycache__` under RO zones.
- **T4** — `sandbox_argv()` takes rw carve-outs from `plan.mutable_paths`
  (materializer rules):
  ```
  mutable path exists && is_file  → file RW bind
  mutable path does not exist     → nearest existing parent dir RW
  mutable path is a directory     → directory RW bind
  ```
- `PYTHONDONTWRITEBYTECODE=1` goes into the **sandbox baseline env**
  (deterministic test environment setting, not a policy workaround).
  The manifest already skips `__pycache__` (stanok.py:694-701).
- `_pretooluse_lock_hook` is removed only in **T5**, after T4 is proven
  e2e (defense-in-depth until then; the hook gives immediate readable
  feedback, EROFS does not).
- The post-turn SHA256 diff stays in ALL phases: evidence, not enforcement.

### Git (I7)

Verified 2026-09-24: `stanok/.git` is a submodule gitlink
(`gitdir: ../.git/modules/stanok`); the parent dir is mounted `:ro`
(sandbox.py:55); `git -C stanok show HEAD:tests/fire_color16_test.py`
returns content. `git show`/`log`/`diff` already work read-only inside the
container; writes fail at the filesystem layer. **Nothing to change —
document only.** The CC-119 workaround (agent cp'ing from `pre-existing/`)
disappears with quarantine in T2.

## Invariants

- **I1:** SessionPlan is the only policy source. After T1 there are no
  independent policy inputs (declared_paths / quarantine / manifest /
  rw_zones / verify paths) outside the plan.
- **I2:** ~~probe failure ⇒ the agent never starts (rc=29)~~ — CANCELED (T2 burned).
- **I3:** NO-OP-PASS requires the declared ticket contract to be already
  satisfied — not merely "current tests are green".
- **I4:** the filesystem (Docker mounts) is the enforcement layer.
- **I5:** the SHA256 manifest diff is evidence only.
- **I6:** the PreToolUse hook survives until T4 e2e PASS.
- **I7:** git configuration is unchanged; documented as verified.

## Phases and executors

All T1–T5 touch `launcher/` (RO in the container — sandbox.py:54-63
rw-mounts only src/tests/docs/scripts/evidence) ⇒ **supervisor-executed**
(precedent: "Supervisor backlog", STATUS.md:387; CONTEXT.md
"supervisor-executed tickets, NOT machine"). The machine's role =
verification via smoke/e2e runs.

| Phase | Content | Executor | Verification |
|-------|---------|----------|--------------|
| T1 | SessionPlan + all 6 consumers on the plan; behavior byte-for-byte | supervisor | tests_harness + doctor + machine smoke run |
| ~~T2~~ | ~~preflight gate (rc=29, NO-OP-PASS), quarantine retired~~ — **CANCELED 2026-09-24** (REVIEW §9, CC-131) | — | — |
| T3 | mount experiment (a/b/c) | supervisor | host-side, no agent |
| T4 | dynamic RW mounts from `plan.mutable_paths` | supervisor | machine e2e (Bash EROFS on protected, RW on mutable) |
| T5 | remove `_pretooluse_lock_hook` | supervisor | machine e2e |

## Byte-for-byte constraint (T1)

T1 changes plumbing, not values: `mutable_paths == declared_paths`,
`rw_zones` = the current hardcoded tuple, quarantine and the hook unchanged. Observable behavior (rc codes, summary.json
fields, file operations, hook decisions, mounts) is identical.
