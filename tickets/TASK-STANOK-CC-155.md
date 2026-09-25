# TASK-STANOK-CC-155 — the generated stack output is dead; consume it or drop it

Supervisor-executed. Follow-up to the CC-148 review (commit `158a0c6`).

## Incident / context

CC-148 (D2) introduced `scripts/stacks/*.toml` + `scripts/gen_stacks.sh`, which
emits **three** outputs:

- `scripts/stacks.generated.sh` — the `STACKS` registry sourced by `run.sh`
  (`run.sh:65`) — **consumed**;
- `scripts/stacks.generated/domains.json` — **no consumer** (only
  `gen_stacks.sh` writes it and `tests/stacks_gen_test.py` asserts its
  contents);
- `scripts/stacks.generated/runtime.list` — **no consumer** (same).

So the "single stack manifest" covers only 1 of the 4–5 real edit sites named
in the audit (L4): `settings.stanok.json` `allowedDomains` is still
hand-maintained, the Dockerfile runtime is still hand-maintained, and
`CLAUDE.md` "Test forms" prose is still a separate copy. Two generated files
are dead weight that *looks* like the source of truth.

Also stale: `scripts/stacks/py.toml` lists `runtime = [..., "uv (pinned
0.5.24)", ...]`, but CC-152 (`1af0b15`) removed `uv run` from the py runner —
`uv` is no longer a runner dependency (it remains a host-side/doctor tool).

## Change (decide via D2; either is acceptable)

- **(A) Consume it.** Generate the `allowedDomains` block into
  `settings.stanok.json` (or a fragment the launcher merges) and the Dockerfile
  runtime list, plus a doctor drift check (manifest ↔ settings/Dockerfile ↔
  docs). Closes the remaining sites in L4/L5.
- **(B) Drop it.** Delete `stacks.generated/domains.json` + `runtime.list` and
  their tests; keep only the `run.sh` registry block. Cheapest; leaves
  settings/Dockerfile manual but no longer *implies* a manifest governs them.
- In both: fix `py.toml`'s `runtime` (`uv` is not a runner dep after CC-152).

## Verification

- (A) doctor drift check red when `stacks/*.toml` and
  `settings.stanok.json`/Dockerfile diverge; `run.sh` behavior unchanged
  (`test_runsh_contract.py` green).
- (B) no reference to the deleted files anywhere; `stacks_gen_test.py` trimmed
  to the surviving output; doctor green.
- Either way: `bash scripts/gen_stacks.sh --check` green on a clean tree.

## Non-goals

- No new stack added.
- Does not touch the `STACKS` registry format or `run.sh` semantics.
