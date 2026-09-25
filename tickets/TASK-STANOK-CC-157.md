# TASK-STANOK-CC-157 — W7 rc=28: actionable message + clean-for-task deny-path preservation

Executor: **operator/supervisor** (launcher zone — the machine cannot write `launcher/`).
NOT a machine ticket (no manifest header; do not feed to `launch.sh`).

## Incident (citation, per §7 primitive-first)

2026-09-25, FIRE-01 launch 1: `/clean-for-task` deleted `stanok/evidence/`, but
`stanok/.claude/settings.stanok.json` has deny entries `["../evidence","../hooks",
"../launcher","../.claude"]`. The W7 gate (`sandbox_config_gate`,
`launcher/stanok.py:351`) then failed closed:

```
ERROR: sandbox.filesystem deny entry resolves to a non-existent path (rc=28)
```

The gate worked correctly (fail-closed is the design, CC-107), but the abort
message names neither the offending entry nor the resolved path, and the
fix (`mkdir -p stanok/evidence`) was discovered by hand.

## Requirements

1. `sandbox_config_gate()` (stanok.py:351) must, on failure, log for EACH
   bad entry: the raw entry, the key (`denyWrite`/`denyRead`), the resolved
   absolute path, and the suggested fix (`mkdir -p <resolved>`). The abort
   string from `early_abort(28, ...)` must carry the same detail.
2. The `clean-for-task` skill (projectSettings) must, before deleting, read
   `stanok/.claude/settings.stanok.json` `sandbox.filesystem` denyWrite/denyRead
   entries, resolve them against `stanok/.claude/`, and either (a) exclude
   still-referenced directories from deletion, or (b) recreate them empty
   after cleanup. The grouped file list shown to the user must mark
   sandbox-referenced paths.
3. Hermetic test in `launcher/` (pytest, existing suite): a settings file
   with a missing deny entry produces a gate failure whose message contains
   the entry, the resolved path, and `mkdir -p`.

## Acceptance

- `doctor.sh` green (existing + new tests).
- Simulated incident: delete `stanok/evidence/` → launch aborts rc=28 with a
  message that names `../evidence`, `/home/hermes/darkcast/stanok/evidence`,
  and `mkdir -p`.
- `/clean-for-task` run on a dirty tree leaves every sandbox-referenced path
  existing afterwards.
