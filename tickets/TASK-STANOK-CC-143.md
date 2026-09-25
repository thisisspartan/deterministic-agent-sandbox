# TASK-STANOK-CC-143 — cli.js patch layer: `patches/` + apply/verify + setup.sh wiring

Supervisor-executed in the **CLI repo** (`~/git/claude-code-2.1.88`), branch
`base`. No machine launch. Part of
`specs/PLAN-cli-js-hygiene-2026-09-25.md` (F2). Enabler for CC-144.

## Incident / context

All 31 commits / 12 hunks of the shipped line are edits inside **single lines**
of a 13 MB minified file (line 2070, 2100s, 4181, 4824, 5433, 7843, 8040 …). They
are effectively unreviewable in `git diff` and brittle to any upstream bump: a
re-bundle silently moves every anchor and no check notices. This is the same
"silent skip" failure class that produced CC-141 (a native code path quietly
declining to act).

## Change

- `patches/` — one `.patch` file per intent (A tracing ×2, B think_off,
  C spinner phase machine, D UI/temp), each with a header: id, target file,
  anchor (the exact minified substring), intent, evidence/incident, source commit.
- `patches/apply.sh` — applies them in order to a fresh `cli.js` (idempotent:
  detect "already applied" by anchor).
- `patches/PATCHES.md` — human index: id → file → anchor → intent → commit.
- `patches/verify.sh` — for each patch, `grep -qF` the anchor in `cli.js`; then
  `node --check cli.js`. Exit non-zero on the first miss. Cheap, no model.
- `setup.sh` — call `patches/verify.sh` before copying the bundle into the build
  context (fail-fast: never ship a drifted bundle).

## Verification

- `bash patches/verify.sh` exits **0** on the untouched `base` bundle.
- Perturbation test: flip one anchor char in a temp copy → `verify.sh` exits
  non-zero (the regression cannot silently return).
- `node --check cli.js` clean; `git rev-parse base:cli.js` unchanged (patches
  dir adds no bundle edit).
- `bash -n patches/*.sh`; `setup.sh` still runs (dry parse).

## Non-goals / residuals

- Does not re-derive the patches from scratch: CC-143 transcribes the **existing**
  12 hunks; it must not change bundle behavior (`base:cli.js` blob stays
  `809caeef…`).
- No upstream-version work, no automated re-basing onto a new vendor bundle
  (that is a later ticket if the pin ever moves).
