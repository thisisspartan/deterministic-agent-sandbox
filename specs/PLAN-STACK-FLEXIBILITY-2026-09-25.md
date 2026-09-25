# PLAN — stack flexibility & maintainability (2026-09-25)

Companion to `specs/AUDIT-STACK-FLEXIBILITY-2026-09-25.md` (findings L1–L8,
S1–S5). **Plan only — nothing executed, no tickets created.** Proposed numbers
CC-146+ (CC-142…145 are taken by the cli.js hygiene line). Each step cites the
incident/evidence class it closes (cli.js-first rule, `CLAUDE.supervisor.md §7`).

## Principles

1. **Task side vs harness side.** Only the task side is de-Pythoned/JS-ified.
   `stanok.py` stays Python (the SDK is Python-only); it is the operator's tool.
2. **One source per fact.** Every stack/rc/doc fact gets exactly one canonical
   location; everything else is generated or doctor-checked.
3. **Evidence before mechanism.** No new abstraction without a named failure it
   prevents (in the audit's L-list) or a measured speed win.
4. **Fail closed, but legibly.** Replace integer-only verdicts with a reason
   string alongside the code.

## Phase 0 — hygiene & drift guards (no behavior change)

- **CC-146 — rotate/split `CONTEXT.md`.** It is 120 663 B and read at every
  supervisor start. Split into `CONTEXT.md` (live state, ≤ ~15 KB) +
  `specs/ARCHIVE/CONTEXT-<wave>.md` for closed waves; add a doctor check that the
  live file stays under a budget. Gate: supervisor can still answer §1 from the
  live file; nothing lost (archives in git).
- **CC-147 — doc/registry drift check.** `specs/STACKS.md` currently documents a
  5-field registry and 2 stacks while `run.sh` has 6 fields and 3 (L5). Add a
  doctor check that parses the `STACKS` heredoc and asserts the field count,
  stack set, and runner commands match what `STACKS.md` + `CLAUDE.md` "Test
  forms" claim; refresh both docs. Gate: doctor red if either doc drifts again.

## Phase 1 — flexibility (the core of the request)

- **CC-148 — single stack manifest.** `stanok/stacks/<name>.toml` per stack
  (ext, glob, name-regex, test-runner, smoke-runner, preflight, domains,
  runtime-packages). A small generator emits the `run.sh` `STACKS` block and a
  settings-domain fragment; the Dockerfile consumes the runtime list. Removes the
  6-field pipe-DSL footgun (L4) and collapses 4–5 edit sites to one file + a
  rebuild. Gate: generated `run.sh` is byte-identical in behavior to today for
  js/py/jq (`test_runsh_contract.py` + `test_runsh_py_stack.py` unchanged green);
  `verify.sh`-style check that the committed generated block matches the manifest.
- **CC-149 — whole-suite mode.** Add `run.sh test --all` (or `suite`) so a
  package/crate-level runner (`go test ./...`, `cargo test`, `npm test`) is
  expressible, and switch `verify_gate` to one suite call per turn instead of
  N per-file spawns (L3, S1, S2). Gate: contract tests; a suite-mode timing note.
- **CC-150 — bootstrap gate for top-level paths.** Today a new top-level file/dir
  is undeclarable (L1), so a fresh Go/Rust project cannot create `go.mod`/`cmd/`.
  Decision needed (audit §7.1/7.3): either (a) a `bootstrap:` declaration kind
  allowed only when `scripts/run.sh` is absent/declared, restricted to a small
  audited set per stack, or (b) a per-ticket `allow_top_level:` header. Gate:
  the carve-out still cannot escape the repo; contract tests for the new gate.
- **CC-151 — stack-agnostic subversion guard.** The pytest-config rc=27 guard
  (L6) is Python-only and blanket-forbids a legitimate `pyproject.toml`. Make it
  manifest-driven: each stack declares its "config that can rewrite the verdict"
  patterns; the guard enforces them uniformly and stops over-blocking py.
  Gate: existing rc=27 tests + a new case per declared stack.

## Phase 2 — speed

- **CC-152 — cheaper test invocation.** In the image, call the runner without the
  `uv run` wrapper (S3) and/or warm a single interpreter; keep `run.sh` as the
  contract. Measure with a fixed ticket before/after (suite wall time). Gate: no
  change to rc semantics; a recorded before/after.

## Phase 3 — runtime-level hygiene (already partly planned)

- **CC-142…CC-145 — cli.js patch line** (`specs/PLAN-cli-js-hygiene-2026-09-25.md`):
  backups, `patches/` layer, correctness/dead code, branch/history decision.
- **CC-153 — llama.cpp pin + patch dir.** The `tool_choice` fix is a loose
  `.patch` with no pinned commit/build/verify (L8). Same `patches/` + `verify.sh`
  pattern as CC-143, plus the server launch flags + the
  `/data/models/chat_template.jinja` markers (`<|think_off|>`/`<|think_on|>`)
  documented in-repo as a typed contract between cli.js and the template.

## Ordering & dependencies

```
CC-146, CC-147            (independent, safe)
CC-148 → CC-149, CC-151   (manifest first; suite mode and guard consume it)
CC-150                    (decision-gated; independent of 148)
CC-152                    (after CC-149 so the suite path is the measured one)
CC-142…145                (independent line)
CC-153                    (reuses CC-143's pattern)
```

## Decision gates (need the operator before code)

| Gate | Question | Blocks |
|---|---|---|
| D1 | Top-level bootstrap allowed? which form? (audit §7.1/7.3) | CC-150 |
| D2 | One stack manifest, or keep the in-place registry? (audit §7.4) | CC-148/149/151 |
| D3 | Is `base` canonical; are `stock`'s remote-compaction and `main`'s B1 think_medium deliberately absent? | CC-145 |
| D4 | Whole-suite contract acceptable, or per-file forever? | CC-149/152 |
| D5 | CLAUDE.md/STACKS.md considered canonical docs (so drift checks gate on them)? | CC-147 |

## Risks / non-goals

- **Do not** rewrite `stanok.py` in another language; do not replace
  `claude-agent-sdk`.
- **Do not** split the sandbox boundary or weaken the contract lock to gain
  flexibility — CC-150 must preserve "tests are immutable".
- A single manifest (CC-148) adds indirection; adopt **only** if D2 = yes, else
  keep the registry and fix just its docs/format (the cheap part of CC-147).
- Speed work must show a measured before/after on a fixed ticket; otherwise it is
  code-for-code (rejected by the cli.js-first rule).
