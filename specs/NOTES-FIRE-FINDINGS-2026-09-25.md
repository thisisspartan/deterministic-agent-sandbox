# NOTES — SPEC-FIRE analysis findings (2026-09-25)

Saved from the post-batch analysis so nothing is lost. Operator decided the
fire tickets are out of priority; these findings stay here for a possible
future TASK-FIRE-07.

## Verified consistent (no action)

- All 6 runs: rc=0, verifier PASS, single turn, `contract_lock_violations: []`.
- Opik traces match evidence 1:1 (6 sessions, 25/46/39/41/65/32 spans,
  windows 14:29–15:23 UTC = 17:29–18:23 +0300, final spans `success=True`).
- `docs/fire.md` matches code: palette nodes (0/32/96/180/240/255), step
  formula (`dst_x = x − wind + choice(−1,0,1)`, decay 1–4), half-block
  rendering with color dedup + `\033[0m`, CLI options, smoke test (120x80,
  33 ms budget).

## Findings (would need a ticket to fix — machine zone)

1. **Ember permanent hot-spot** — `stanok/src/fire/simulator.py`, `step()`:
   an ember that reaches row 0 is clamped and never removed/decayed; it
   rewrites `buffer[0][x] = 250–255` every tick → permanent hot line at the
   top of the screen.
2. **Embers never appear in the live app** — `stanok/src/fire/cli.py`,
   `FireApp._step()` calls `update_wind()` + `step()` but never
   `spawn_sparks()`; feature #3 (floating embers) is dead code in the
   running animation. Ticket gates covered the simulator method only, not
   the integration.
3. **Stale file** — `stanok/docs/wordfreq.md` (committed leftover from the
   previous task) still present in `docs/`.
