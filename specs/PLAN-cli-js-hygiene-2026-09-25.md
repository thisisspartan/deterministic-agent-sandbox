# PLAN — cli.js patch-line hygiene (2026-09-25)

Supervisor-executed. These tickets live in the **CLI repo** (`~/git/claude-code-2.1.88`),
NOT in `stanok/` — there is no TDD harness for a 13 MB vendor bundle, so the
machine is **never launched** for them. Proof per ticket = the CLI repo's own
`patches/verify.sh` + `node --check` + (for behavioral changes) one live smoke.
All four tickets are registered but **not started** (operator said "plan only").

## 1. What was reviewed

The operator's own patches to `cli.js`. Branch holding the **shipped bundle** is
`base` (HEAD `09fc14f`); its tree `cli.js` blob is `809caeef`, and the file's
sha256 = `10ff56ce84f3d6c4…` = `setup.sh:42 CLI_JS_SHA` → **`base` is exactly what
`setup.sh` copies into the image.** `base` = `origin/main` (`c8cd253`, vendor
baseline) + **31 commits**.

Reproduce the net diff at any time (no artifact kept in-repo):

```sh
cd ~/git/claude-code-2.1.88
git diff origin/main..base -- cli.js                 # 12 hunks vs vendor baseline
git log --oneline --reverse origin/main..base        # the 31 commits
```

Sibling lines (all diverged from `origin/main`, none merged into `base`):

| ref | commit | commits beyond origin/main | note |
|---|---|---|---|
| `origin/main` = `origin` = `c8cd253` | `397ffc36` | 0 | vendor baseline |
| `stock` | `5e870b9b` | 17 | carries the remote-compaction experiment (Gemini/Mistral) — **absent from base** |
| `base` | `809caeef` | **31** | **shipped** |
| `main` | `29fbe302` | 8 | carries B1 think_low/think_medium — **absent from base** |
| `dev` | `8dd4f5cc` | 8 | (checked out in another worktree) |
| `feature/git-command-protection` | `6ddd5776` | 3 | |

## 2. Net patch inventory (12 hunks), by intent

- **A. Tracing** — `thinking_output` attr on `llm_request` (line 2070, `da4c167`);
  OTLP exporters JSON→protobuf `Cl1→Ft4`,`Vl1→Gt4` (line 2102, `4b78382`).
  Live-confirmed by the SMOKE-01 trace (2862 spans in Opik ⇒ collector accepts protobuf).
- **B. `<|think_off|>` marker** — 3 live sites (`oWK` preamble, `aWK`,
  summarizer `systemPrompt`) from `e8be6c7`/`b707963`; plus a **net-zero** pair
  `ddf150b` (inject on tool_result batches) + `0285301` (revert).
- **C. Spinner phase machine** (~22 commits) — `globalThis.__phase/__in/__out/`
  `__lt/__ltt/__t_decode/__end` in ~8 sites (lines 2161, 2203, 4181/4183, 4824,
  7843); PREFILL/THINKING/DECODE from SSE, live ∴ snippet, `mK` k-notation,
  phase-only status line. The `/metrics` poller (feature J) was added then
  dropped — net result is server-dependency-free (good).
- **D. Behavior/UI** — context indicator always shown (line 8040, `f6442fb`);
  effort notification suppressed (line 5433, `df53e47`); `STANOK_TEMP`
  (line 7843, `09fc14f`).

## 3. Findings → tickets

| # | Severity | Finding | Evidence | Ticket |
|---|---|---|---|---|
| F1 | med | Two committed **full-bundle backups** `cli.js.bak-preM-20260917` (13 050 416 B) and `cli.js.bak-preTemp-20260924` (13 050 253 B) — ~26 MB in a `.git` already at 362 MB, no `.gitignore` in the repo. | `git ls-files \| grep bak-pre` | **CC-142** |
| F2 | med | Minified one-line edits are invisible to review and brittle to upstream bumps; no mechanical re-apply, no drift check. | 31 commits, 12 hunks, all in single lines | **CC-143** |
| F3 | **bug** | `STANOK_TEMP`: `parseFloat(process.env.STANOK_TEMP)\|\|1` cannot express `0` (falsy → 1) and silently swallows invalid input. | line 7843 | **CC-144** |
| F4 | med | `<|think_off|>` is a **literal prompt string** duplicated at 3 sites; if the model's chat template does not treat it specially, the coupling is undocumented and drifts silently. | 3× `grep '<|think_off|>'` | **CC-144** |
| F5 | low | Gutted effort code: `function PvK(q,K){return}` + `P78` + a call site that computes `jx=PvK(…)` and gates a `useEffect`. | line ~5433 | **CC-144** |
| F6 | med | `globalThis.__*` telemetry is mutable global state duplicated across ~8 sites; history already shows two fixes caused by double-tap/garbling (`2161933`, `12d0e9c`). | commits | **CC-144** |
| F7 | decision | Six divergent branch lines; no declared canonical; `stock`'s remote compaction and `main`'s B1 think_medium are **not** in the shipped bundle — intended or drift? | divergence counts | **CC-145** |
| F8 | decision | History rewrites (purge the backups from history; collapse add/revert `ddf150b`+`0285301`) are **destructive** and must be an explicit operator call, separately from CC-142. | — | **CC-145** |

## 4. Ticket order & gates

1. **CC-142** (safe, tree-only) → `git rm` the two backups + `.gitignore`; gate:
   `git status` clean, `cli.js` blob unchanged (`git rev-parse base:cli.js`).
2. **CC-143** (enabler) → extract `patches/`, add `apply.sh` + `PATCHES.md` +
   `verify.sh`; gate: `verify.sh` exits 0 on the untouched bundle and fails
   non-zero when an anchor line is perturbed; `node --check cli.js`; wire the
   call into `setup.sh` as fail-fast.
3. **CC-144** (behavioral) → F3/F4/F5/F6 in one bundle; gate: `verify.sh`,
   `node --check`, plus one live smoke with `STANOK_TEMP=0` proving `temp=0`
   reaches the request body.
4. **CC-145** (decision) → branch consolidation **and** the F8 history-rewrite
   decision; no code change until the operator rules.

CC-142 and CC-143 touch no executable semantics → they cannot regress the shipped
image. CC-144 changes the bundle → requires a smoke before it is trusted.
CC-145 gates on the operator.

## 5. Open decisions for the operator (CC-145)

1. Is `base` the canonical line (declare it, archive the others)?
2. Remote compaction (`stock`) and B1 think_medium (`main`) — deliberately
   excluded from the shipped bundle, or missing by accident?
3. Purge the 26 MB of backups from **history** (`git filter-repo`), or only from
   the tree? Same question for the add/revert pair collapse.
4. Accept `STANOK_TEMP` default `1` (bundle) vs the server default (`0.2`)?

## 6. Non-goals

- No upstream version bump, no `package.json`/vendor changes.
- No change to sandbox/`AC()`/`yn6()` semantics (CC-141 territory).
- No machine launch: these tickets are not `stanok/` TDD work.
- History rewrite is **not** performed under CC-142/143/144 — it is CC-145's
  decision only.
