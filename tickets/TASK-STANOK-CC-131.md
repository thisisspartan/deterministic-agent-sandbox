# TASK-STANOK-CC-131 — Burn T2: cancel the preflight gate (probes/oracle/rc=29/30), keep KISS

Supervisor-executed. Operator decision 2026-09-24, after the "A vs B" review grounded in the
cc119-fire16/-retry1/-retry2 traces. Follows `specs/REVIEW-KISS-CLI-FIRST-2026-09-24.md` §9.

## Decision

T2 is **cancelled in full**. Variant A (KISS) was chosen over continuing T2:

- **Probes / `oracle:` / rc=29 / rc=30** — not built.
- **Quarantine retirement** — not done; quarantine stays as-is.
- **`exit 29` ("task is infeasible")** — not added to CLAUDE.md; agent self-assessment would
  contradict T2-B's own goal (move status ownership to the host) and was already rejected as
  part of T2-A.
- **`mutable_tests`** — not introduced; `edit:` (CC-125) already is that mechanism.
- **Host loop-abort on "N identical CONTRACT-LOCK DENY"** — not built; separate ticket only
  under a future incident with evidence. TURN-TIMEOUT (1800 s) is enough today.

## Why (evidence)

CC-119 had **two** independent causes, and neither needs a preflight:

1. The contract-lock hook denied a legitimate in-place edit of a pre-existing test
   (fire16 `rc=143`, retry1 1800 s stall). Closed by **CC-125**: `edit: <path>` → `SessionPlan`
   → `prepare_workspace` does not quarantine it → hook / contract_lock exempt it.
2. The ticket was mathematically infeasible (max flame-body heat 0.6938 < required 0.75).
   Closed by the **grill**: retry2 PASSed in 276 s after the header was fixed — no probes ran.

Per REVIEW §6, a new harness mechanism must cite either an incident with `evidence/` or a native
primitive it replaces. probes/oracle/rc=29/30 cite neither: infeasible tickets die in the grill,
and NO-OP is already handled by W2.4. Building them would be exactly the "mechanism added per
incident and never removed" pattern the review named as the root cause.

## Change

1. Delete `specs/PLAN-T2-PREFLIGHT-2026-09-24.md`.
2. Remove the T2 placeholder `probe_specs` from `SessionPlan` (stanok.py) and its 6 use sites
   across the tests harness — code-for-a-cancelled-plan.
3. Mark T2 cancelled in `specs/REVIEW-KISS-CLI-FIRST-2026-09-24.md` (§0/§2.1/§7 + new §9),
   `CONTEXT.md`, `specs/STATUS.md`, `specs/SPEC-SESSION-PLAN-2026-09-24.md`.

## Verification

`py_compile`; `doctor.sh` — **115 passed, 2 skipped**.

## Result (2026-09-24) — DONE

T2 burned. CC-125 `edit:` + W2.4 + host-side `verify_gate` are the standing answer for the CC-119
class. T3–T5 remain deferred (REVIEW §5), untouched by this cancellation. Ticket number 131 is the
next-free advance in CONTEXT.md.
