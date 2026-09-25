# TASK-STANOK-CC-160 — Ticket template: mandatory manifest header + run.sh existence line

Executor: **operator/supervisor** (`CLAUDE.supervisor.md` §1 ticket format).
NOT a machine ticket.

## Incident (citation, per §7)

2026-09-25, FIRE-01:
- launch 2 → rc=13: the ticket had no manifest header; `parse_ticket_header`
  (`launcher/stanok.py:630`) requires leading `impl:`/`test:`/`docs:`/`edit:`
  (or `reset: none`) lines and fails closed otherwise.
- launch 3 → rc=13 (CC-133): the ticket declared `impl: scripts/run.sh` as a
  CREATE, but `run.sh` is pre-existing infrastructure in this repo —
  create-paths must not exist. Additionally all test files were named
  `test_*.py` while the `run.sh` STACK REGISTRY (py stack) claims only
  `*_test.py` — unclaimed test files fail the gate (rc=1) / are refused (rc=2).

Both were supervisor authoring errors, burned two launches each fixable in
the ticket text before any container start.

## Requirements

1. `CLAUDE.supervisor.md` §1 (ticket format) must mandate, for every machine
   ticket:
   - a manifest header as the first lines: one `impl:`/`edit:`/`test:`/
     `docs:` line per deliverable (`#`-title and blank lines allowed in the
     header; the first other line ends it);
   - a line `run.sh: exists` or `run.sh: bootstrap` stating the entrypoint
     state (bootstrap only when `scripts/run.sh` is ABSENT — CC-154);
   - test-file naming per the stack registry (py: `tests/**/*_test.py`;
     js: `tests/**/*.test.js`).
2. The supervisor pre-launch checklist (§2) gains a step: verify every
   `impl:`/`test:`/`docs:` path does NOT yet exist and every `edit:` path
   DOES exist (mirrors CC-133's check, cheaply, before burning a launch).

## Acceptance

- Template in `CLAUDE.supervisor.md` contains the three mandated elements.
- A ticket authored from the template passes `parse_ticket_header` and the
  CC-133 create/edit check on first launch (no rc=13).
