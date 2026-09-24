# TASK-STANOK-CC-128 — Kill-list 2.3: align the window preflight with cli.js's clamp

Supervisor-executed. Follows `specs/REVIEW-KISS-CLI-FIRST-2026-09-24.md` §8 (#3).

## Finding

`preflight_server` (`stanok.py:345-348`) fails the run (rc=20) when the server's
`n_ctx < STANOK_REQUIRED_WINDOW`. But cli.js does not use the env window as-is:
`rQ(q){ … _ = Math.min(Z18(q), o3Y); if (CLAUDE_CODE_AUTO_COMPACT_WINDOW) _ =
Math.min(_, Y); return _ - K }` — the effective compaction window is
**min(the model's real window, the env override)**. So the harness can demand
123000 while cli.js would only ever compact within a smaller real window. That
is a harness-side policy stricter than the native behaviour it is trying to
protect, and it is stated as fact in the trace (`PREFLIGHT: server n_ctx=123136
>= required window 123000 — OK`).

## Change

Investigate first (this ticket is verification-led, not a blind edit):

1. Determine `Z18(q)` — how cli.js derives the model's real context window
   (per-model table / `--model` / fallback). Confirm whether, for
   `Qwen3.8-27B-MTP` served locally, `Z18` is known or falls back to a constant.
2. If cli.js clamps below `STANOK_REQUIRED_WINDOW`, the preflight requirement is
   the wrong number: compare `n_ctx` against the **effective** window
   (min(model window, env)) — or, if `Z18` is unknowable for a local model, drop
   the preflight comparison to a documentary check and leave the clamp to cli.js.
3. Record the finding in `specs/` and adjust `preflight_server` / README so the
   documented meaning of `STANOK_REQUIRED_WINDOW` matches what is enforced.

Outcome may be code (align the comparison) or docs-only (if the enforced value
already equals the effective window). Do not change the number without the
source fact.

## Verification

Whatever changes: `py_compile`; `doctor.sh` green; `test_launcher_preflight.py`
green.
