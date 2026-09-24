# TASK-STANOK-CC-123 — Kill-list 3.2 residual: remove dead `(rc=25)` wording

Supervisor-executed. Follows `specs/REVIEW-KISS-CLI-FIRST-2026-09-24.md` §3.2.

## Finding

The image preflight (`preflight_image`) was already moved off the launch path by
CC-106: nothing calls `early_abort(25)` in the launcher any more; `preflight_image`
is reached only from the doctor check (`test_doctor.py::test_docker_image_digest_matches`).
Its log lines and the supervisor's stop-condition list still advertised **`rc=25`**,
a code that is now unreachable — misleading the operator into looking for a launch
failure that cannot occur.

## Change

- `launcher/stanok.py`: replace `(rc=25)` in the six `PREFLIGHT-IMAGE` log lines
  with `(doctor image preflight)` — the logs are doctor output, not a launch rc.
- `CLAUDE.supervisor.md` §4: drop `rc=25` from the stop conditions; note that image
  provenance (digest / runner availability) is a `doctor.sh` check, so the remedy is
  `./setup.sh`, not a ticket retry.

## Non-goals

No change to `preflight_image` / `_stack_preflights` themselves (that is the §3.2 body,
already satisfied by CC-106 — a separate module split would be refactoring without an
incident). No behavior change; wording only.

## Verification

`py_compile`; `doctor.sh` green (113 passed, 2 skipped). No test asserted on the wording.
