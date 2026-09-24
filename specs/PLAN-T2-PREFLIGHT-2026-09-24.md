# PLAN: T2 — Preflight gate (rc=29), quarantine retirement

Status: **DECIDED (2026-09-24) — Option B adopted.** The KISS / over-engineering
review is done: `specs/REVIEW-KISS-CLI-FIRST-2026-09-24.md`. Verdict: retire
quarantine + keep the W2.4 backstop + honest NO-OP semantics (Option B, §6).
§§1–4 (probes, `oracle:`, rc=29/30, `probe:` header, R1–R10 mechanics) are
**rejected/deferred** — none of those mechanisms will be implemented. §6 stays
as the rationale record.
Spec: `specs/SPEC-SESSION-PLAN-2026-09-24.md` (phase T2, invariants I3, I6).
Executor: SUPERVISOR (`launcher/` is RO in the container); the machine
verifies via smoke runs only.

## 0. Goal

Host-side preflight probes run BEFORE the agent starts. The preflight state
machine replaces quarantine as the stale-artifact gate:

```
ticket (probe: <name>)
    |
    v
PREFLIGHT (host, before container)
    |-- FAIL        -> rc=29, summary.json, agent NEVER starts
    |-- SATISFIED   -> probe_result=NO-OP-PASS, rc=0, summary, no agent
    |-- NEEDS_WORK  -> materialize (no-op in T2) -> AGENT (current flow)
```

NO-OP-PASS semantics (I3): the declared ticket contract is already satisfied
without any change — NOT "all current tests are green".

## 1. v3 architecture (6 stages, per master plan)

- **Stage 0** — settings hotfix (exact target JSON in R9).
- **Stage 1** — probe support + host supervisor in `main()` BEFORE
  `run_sandboxed()`; `_run_probe_safely` (`python3 -I -s -B`,
  `start_new_session=True`, killpg on timeout, `STANOK_PROBE_TIMEOUT_S=120`);
  parser meta-lines; quarantine REMOVED from `prepare_workspace`;
  `oracle:` lines -> `oracle_manifest` {rel: sha256}.
- **Stage 2** — first probes: `probes/static-check.py`,
  `probes/infeasible-check.py` (exercises rc=29).
- **Stage 3** — eight hermetic tests (`launcher/tests_harness`).
- **Stage 4** — docs + doctor green.
- **Stage 5** — five verification runs (smoke NEEDS_WORK -> rc=0/PASS;
  infeasible -> rc=29 no SESSION START; idempotent re-run -> NO-OP-PASS;
  etc.).

## 2. Resolved decisions (v3)

- **O1**: NO-OP-PASS (SATISFIED) -> **rc=0**.
- **O2**: unknown/missing probe name -> **rc=13** (ticket parse error).
- **O3**: probe crash/timeout/garbage JSON -> **rc=30** (PROBE-INFRA-FAIL,
  new code; infra failure, NOT a ticket defect).
- **O4**: insertion point = `main()` on the host, before `run_sandboxed()`.

## 3. Supervisor review fixes (R1–R10)

- **R1** — `TRUSTED_PROBES_DIR` must be
  `os.path.join(os.path.dirname(REPO_ROOT), "probes")` = `darkcast/probes`
  (supervisor zone, next to `specs/`, `tickets/`). The v3 draft's
  `os.path.join(LAUNCHER_DIR, "..", "probes")` = `stanok/probes` — wrong zone.
- **R2** — Parser: add `probe:` and `oracle:` as RECOGNIZED meta-lines;
  KEEP the `break` on unknown lines (W2.1: header block ends at the first
  non-matching line; body paths must never be matched). "Устранить break"
  from the v3 draft is rejected.
- **R3** — Preflight guard: `if not in_container():` — preflight runs in
  BOTH host modes. The v3 draft's `and not args.no_sandbox` would skip it
  in no-sandbox host mode.
- **R4** — rc=30 must be added to the supervisor contract
  (`CLAUDE.supervisor.md` stop conditions: infra failure, do NOT retry the
  ticket) + SPEC/README rc tables.
- **R5** — Unify NO-OP-PASS exit code: preflight SATISFIED rc=0 AND W2.4
  zero-writes backstop rc=0 (currently backstop is rc=1). Verdict C is read
  from `probe_result`, not rc.
- **R6** — Probes MAY invoke `scripts/run.sh` on the host (read-only w.r.t.
  code; the host already runs the full stack via doctor — "no run.sh on
  host" is over-cautious). Probe env: `PATH=/usr/local/bin:/usr/bin:/bin`,
  `HOME=$HOME`, `TMPDIR` set — not `HOME=/nonexistent`.
- **R7** — Oracle files must be denied by `_pretooluse_lock_hook`: add
  `oracle_paths` to `SessionPlan` and include them in the deny check
  (they are immutable).
- **R8** — Marker timing hole: host-side abort (rc=29/30/0) happens BEFORE
  `run_sandboxed` writes `.running` -> `launch_background` parent would
  return rc=17 although summary.json was written. Fix: write the `.running`
  marker in `main()` (host) BEFORE `run_preflight`.
- **R9** — Stage 0 exact target settings JSON (current -> target):
  - `sandbox.filesystem.denyWrite`:
    `["../evidence", "../hooks", "../launcher", "../.claude"]`
    -> `["../evidence", "../probes"]`
  - `sandbox.filesystem.denyRead`:
    `["../hooks", "../launcher", "../evidence", "../.claude"]`
    -> `["../hooks", "../launcher", "../evidence", "../probes"]`
- **R10** — Double ticket parsing (host + container) is acceptable, but the
  `early_abort` helper MUST write summary.json in the exact standard format
  (supervisor reads it uniformly for rc=29/30/0 and normal finishes).

## 4. Open questions (need operator decision)

- **Q1**: rc=0 for NO-OP-PASS in both places (preflight + W2.4 backstop) — ok?
- **Q2**: allow `scripts/run.sh` inside host probes — ok?
- **Q3**: `.running` marker written in `main()` before preflight — ok?
  (Changes rc=17 semantics: 17 = death before the very start of the host branch.)

## 5. Surface fixes applied (2026-09-24)

- Dirty `stanok/` tree from the t1-smoke run (uncommitted `src/smoke.js`,
  `tests/smoke.test.js`, `docs/smoke.md`) committed as `d434f74`
  ("chore: save state before T2 review"). Tree is clean; rc=22 cannot fire
  on the next launch.

## 6. KISS / over-engineering audit (for the review agent)

**Principle (operator):** the agent inside the container must work FREELY.
Launcher mechanisms must be minimal; every gate is a crutch (костыль) until
proven necessary.

| Mechanism | Problem it solves | Cost | KISS alternative |
|---|---|---|---|
| Quarantine removal | Stale artifacts mask NO-OP (real bug: re-run of a satisfied ticket re-does the work) | Low | **KEEP** — this is the core T2 value |
| W2.4 zero-writes backstop | NO-OP detection without probes | Low | **KEEP** until preflight proven, then retire |
| Host probes + rc=29/30 | Fail-fast on infeasible tickets; SATISFIED gate | HIGH: parser meta-lines, `_run_probe_safely`, 2 new rc codes, marker timing (R8), settings changes (R9), probe files in supervisor zone, double parsing | Supervisor refuses to launch infeasible tickets itself (grill phase); W2.4 already detects NO-OP (verdict C) |
| `oracle:` / oracle_manifest | Immutability of arbitrary declared files | MEDIUM: new header line, manifest, hook extension (R7) | `contract_lock` already protects `tests/` + `scripts/run.sh` via the manifest; extend `protected_paths` to declared non-mutable files only if a real ticket needs it |
| `probe:` header line | Probe selection per ticket | MEDIUM (parser + rc=13 branch) | Drop with probes |

**Option A (full v3):** all of the above.
**Option B (KISS):** quarantine removal + W2.4 as the NO-OP gate (rc unified
per R5) + honest NO-OP-PASS semantics (I3). No probes, no oracle, no
rc=29/30, no settings changes. Infeasible tickets surface as defect B
(agent tries, verifier FAIL, supervisor refines the ticket) — handled by
existing rules.

**Supervisor conclusion:** the core T2 value is quarantine retirement +
honest NO-OP semantics. Probes and oracle are likely crutches: the
supervisor already grills tickets before launch (infeasible tickets should
die in grill, not in a probe), and the contract lock already covers the
immutability cases that have actually occurred. Recommend **Option B**
unless fail-fast on infeasible tickets is a hard operator requirement.

## 7. Evidence legend — root copies (2026-09-24)

Copies of the latest flame traces and the final test run, placed at the
darkcast root for the review agent. Sources: `stanok/evidence/<label>/`
(each copy = `summary.json` + `launcher.stdout.log`).

| Root dir | Label | rc / verdict | What it shows |
|---|---|---|---|
| `cc119-fire16/` | cc119-fire16 | 143 / FAIL (VERIFY-FAIL) | First fire16 attempt: RED confirmed, 2x CONTRACT-LOCK DENY on pre-existing `tests/fire_color16_test.py` (lock working as designed), verifier FAIL (16-mode SGR test), then SIGNAL 15 — run interrupted at 3033 s. |
| `cc119-fire16-retry1/` | cc119-fire16-retry1 | 1 / FAIL (VERIFY-FAIL) | Retry: RED confirmed, 1x CONTRACT-LOCK DENY, then `TIMEOUT: turn 1 exceeded 1800s (silent stall) -> interrupt`. The stall, not the code, killed the run. |
| `cc119-fire16-retry2/` | cc119-fire16-retry2 | 0 / PASS (CLEAN-FIRST) | Final flame run: 1 turn, 285 s, cache hit 93.8%, verifier PASS. Commit `7482d15` (fire16 ramp + `--probe` swatch card). |
| `t1-smoke/` | t1-smoke | 0 / PASS (CLEAN-FIRST) | Final T1 test run after the SessionPlan refactor: 1 turn, 75 s, RED confirmed on `tests/smoke.test.js`, 3 HOOK-CALLs, verifier PASS, `contract_lock_violations: []`. Commit `b27d00c`. |

Reading guide: `summary.json` = machine-readable verdict (rc, verifier,
probe_result, tokens, failures); `launcher.stdout.log` = the host-side
trace (DECLARED PATHS, QUARANTINE, HOOK-CALLs, CONTRACT-LOCK DENY,
VERIFIER, RUN FINISHED). The QUARANTINE lines in all four traces are the
behavior T2 retires (stale declared artifacts moved aside before the agent
starts).
