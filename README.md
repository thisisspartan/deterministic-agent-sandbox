# darkcast — control room for the stanok machine

This repo is the SUPERVISOR zone: coordination, specs, tickets, and the
launch tooling. The machine itself (runner, sandbox, doctor, image) lives
in the `stanok/` git submodule — its documentation is `stanok/README.md`.

## Layout

```
CLAUDE.supervisor.md    — the supervisor role (grill -> spec -> ticket ->
                          launch -> validate). Deliberately NOT named
                          CLAUDE.md: a root CLAUDE.md would be auto-loaded
                          into the machine session (role leak, rc=24).
                          Injected explicitly via --append-system-prompt-file.
CONTEXT.md              — persistent facts (read at session start)
specs/                  — STATUS.md (task state) + SPEC-*.md (requirements
                          + acceptance criteria)
tickets/                — machine tickets (TASK-STANOK-CC-NNN.md); the
                          machine sees ONLY the ticket
P0-launch.sh            — interactive Claude Code -> local llama-server
                          session entry point (env-configurable, no repo paths)
opik-traces.py          — (darkcast-specific) Opik trace-diagnosis helper
                          (client-side filter, CC-159)
patches/                — (darkcast-specific) llama-server patches (see
                          patches/PATCHES.md)
stanok/                 — the machine (git submodule)
```

## How a ticket flows

1. Supervisor grills the requirement -> `specs/SPEC-<slug>.md` +
   `tickets/TASK-STANOK-CC-NNN.md` (self-contained; manifest header +
   `run.sh:` line are mandatory).
2. Gate: `stanok/` tree must be clean (the machine fails closed on a dirty
   tree, rc=22); manifest paths pre-checked.
3. Launch: `stanok/launch.sh run <ticket> <label> --follow` as ONE background
   Bash call (`--follow` is the sole background flag — it blocks until the
   run is terminal, so the completion notification IS the verdict trigger).
4. Verdict: read `stanok/evidence/<label>/summary.json` exactly once
   (rc=0 + verifier PASS + no contract_lock_violations = DONE).

Full pipeline discipline: `CLAUDE.supervisor.md` §3. Machine internals
(setup, running, architecture, env table): `stanok/README.md`.
