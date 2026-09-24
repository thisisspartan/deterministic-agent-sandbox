# TASK-STANOK-CC-130 — Kill-list 2.D (spike): native Stop-hook `block` vs the hand-rolled retry prompt

Supervisor-executed. Follows `specs/REVIEW-KISS-CLI-FIRST-2026-09-24.md` §8.D.

## Finding

The retry loop is hand-rolled: on verifier FAIL the harness assembles an XML
`<verification_result>` block and calls `client.query()` again on the same
session (`stanok.py:1245-1261`). cli.js already has the primitive: a hook may
return `{decision: enum(["approve","block"]), reason, stopReason, continue}`
(schema `wBz`), and a `block` decision **re-invites the model in the same
session** with `reason` as the follow-up. The harness's hooks are in-process SDK
callbacks running on the host (where `verify_gate` already runs, `stanok.py:566`),
so a `Stop` hook could compute the verdict natively.

## Change (spike — report, do not wire blindly)

1. Prove the semantics on the pinned 2.1.88: does a `Stop` hook returning
   `decision:"block"` + `reason` actually re-prompt (versus ending the turn)?
   Minimal repro against the local server; capture the transcript.
2. Check the interaction with the external verdict contract: today the host loop
   returns `rc`/`summary.json` after each turn. A native `block` loop moves the
   retry *inside* one `query()`, so the harness must still see the final FAIL to
   write `summary.json` — confirm `Stop` fires per-turn and the SDK still yields
   a `ResultMessage`.
3. Check the double-verdict risk: `verify_gate` would run from the hook AND from
   the host loop after the turn — decide which becomes the single arbiter.
4. Write the verdict in `specs/` (adopt / reject + why). Only a follow-up ticket
   under §6 (incident evidence or native primitive named) may rewire the loop.

## Non-goals

No code change to `run_continuous_session` in this ticket. The retry loop keeps
working; the spike decides whether it is retired.

## Result (2026-09-24) — REJECT: the premise was wrong

Source read (pinned 2.1.88, no live run needed): the generic hook-result parser
does `if (J.continue===!1){ H.preventContinuation=!0; if(J.stopReason)H.stopReason=… }`
— `continue:false` **stops** the turn, it does not re-invite the model. And
`decision:"block"` lowers to `permissionBehavior:"deny"` + `blockingError` — the
permission path for PreToolUse, not a Stop re-prompt. There is **no** primitive in
2.1.88 for "block the stop and inject a new prompt".

Verdict: keep the hand-rolled `<verification_result>` + `query()` loop — it is not
a crutch over a native feature, it is required (the verdict is external/host-side).
REVIEW §1/§2/§8.D corrected: the earlier "CLI сам может пере-пригласить модель"
claim was optimistic and is now retracted. No code change.
