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
CONTEXT.md              — (darkcast-specific) persistent facts (read at
                          session start)
specs/                  — STATUS.md (task state) + SPEC-*.md (requirements
                          + acceptance criteria) — darkcast-specific except
                          specs/STACKS.md (the shared stack docs)
tickets/                — (darkcast-specific) machine tickets
                          (TASK-STANOK-CC-NNN.md); the machine sees ONLY
                          the ticket
P0-launch.sh            — interactive Claude Code -> local llama-server
                          session entry point (env-configurable, no repo paths)
opik-traces.py          — (darkcast-specific) Opik trace-diagnosis helper
                          (client-side filter, CC-159)
patches/                — (darkcast-specific) out-of-tree patch provenance
                          (CC-153); content local-only, the public tree keeps
                          the folder placeholder only
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
(setup, running, env table): `stanok/README.md`; architecture (call chain,
module map): `stanok/ARCHITECTURE.md`.

## Releasing a Stanok version

The parent pins a specific stanok commit, never a floating `main`. Publishing
a new version is a controlled four-step release (no new mechanism — this is
the procedure already followed, e.g. `c8c7bab`):

1. **Candidate check.** `git -C stanok status --porcelain` is empty;
   `git -C stanok log --oneline origin/main..main` contains ONLY commits
   whose verdict was accepted — for each, `stanok/evidence/<label>/summary.json`
   shows `rc=0`, `verifier=PASS`.
2. **Publish stanok.** Push `main` to BOTH remotes (`origin` and `github`).
   A parent pin must point at an object reachable from the public remote, or
   `git clone --recurse-submodules` breaks for external users.
3. **Pin commit in the parent.** `git add stanok`, verify the staged range
   with `git diff --cached --submodule=log` (exactly the intended commits),
   commit as a single-purpose `chore: pin stanok <sha> — <reason + evidence
   label>`, push to both remotes.
4. **Record.** Dated entry in `CONTEXT.md` (the supervisor log; transcripts
   are not memory).

Machine payload cleanup (operator decision 2026-10-15): the ticket-generated
payload in `src/`, `tests/`, `docs/` is validation material, not product —
after a ticket is DONE and validated, remove it from the tree (`git rm`,
keep the `.gitkeep` placeholders: the directories must exist) before the
release push, so the public stanok HEAD carries infrastructure only. History
is NOT rewritten (same policy as `specs/`/`tickets/`). Exception:
`tests/runtime_contract_test.py` + `docs/runtime-contract.md` are the
runtime-contract guard (CC-261) and a harness dependency — they stay tracked.

Division of documents: this README = the process (normative); `CONTEXT.md` =
the log of each actual release; `specs/` = requirements and accepted
decisions only.

## Verifying this project from the outside

External audits must fix a SHA (pin or HEAD) before checking anything: verify
against GitHub API contents + raw files at that SHA, never HTML pages or
cached snippets (directory listings are not crawlable; mixing snippets of
different dates produces era-confused conclusions).

What the public `stanok/README.md` documents is the mechanism, not the
deployment: the default `STANOK_SERVER_URL=http://127.0.0.1:8080` is public,
but the inference host and Opik IPs are not hardcoded in public files — they
come from the environment. The supervisor layer (ticket-level retries,
stop-conditions) is described in this repo's `CLAUDE.supervisor.md`, not in
the stanok README.
