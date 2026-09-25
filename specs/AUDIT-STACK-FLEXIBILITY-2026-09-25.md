# AUDIT — stack flexibility & maintainability (cli.js + stanok + llama.cpp), 2026-09-25

Read-only audit. Nothing changed. Plan: `specs/PLAN-STACK-FLEXIBILITY-2026-09-25.md`.
Goal (operator): fewer костыли/грабли, faster runs, a more understandable and
maintainable repo for **universal tasks**; not tied to Python/JS. Per-language
Docker image rebuilds are an accepted direction, **not** a goal. Flag every
place that removes flexibility.

## 0. Method

Read the real sources, not memory: `stanok/Dockerfile`, `scripts/run.sh`,
`launcher/stanok.py` (2032 lines), `launcher/sandbox.py`, `setup.sh`,
`.claude/settings.stanok.json`, `CLAUDE.md`, `specs/STACKS.md`,
`darkcast/README.md`, `P0-launch.sh`, the cli.js branch `base`, and the
llama-server config recorded in `grok-kimi/specs/PROBLEM-thinking-overhead.md`.

## 1. Stack map (who runs what)

| Layer | Lives where | Language | Mutable? |
|---|---|---|---|
| Task code + tests | `stanok/{src,tests,docs,scripts}` | **per-ticket** (py/js/jq today) | rw, only these 4 zones |
| Project test entrypoint | `stanok/scripts/run.sh` | bash + registry | rw only if declared |
| Harness (gates, verdict, plan) | `stanok/launcher/` | Python 3 + `claude-agent-sdk` | supervisor-only, RO in container |
| Container image | `stanok/Dockerfile` | debian bookworm | rebuild = new digest |
| Model runtime | `~/git/claude-code-2.1.88/cli.js` | Node, patched, **frozen** | operator patches |
| Model server | 192.168.8.131:8080, `llama.cpp` + `/data/models/chat_template.jinja` | C++ (remote) | operator |

## 2. What is already flexible (do not rebuild this)

Credit where due — the design is **not** naive:

- `scripts/run.sh` has a **STACK REGISTRY** (`run.sh:58-60`) and generates its own
  usage text from it (`stack_alts`, `run.sh:63-72`). The runner command lives in
  exactly one place; `run.sh:30` calls it "the single stack extension point".
- `security` path validation (`validate_path`, `run.sh:84-96`) and the
  unclaimed-test-file rule (`run.sh:186-221`) are stack-independent.
- `launcher/stanok.py` never invokes pytest/node directly — it shells out to
  `bash scripts/run.sh list|test` (`_run_one_test:724`, `verify_gate:767`).
- `specs/STACKS.md` exists and documents the 3-place model.
- The Dockerfile (`:3`, `:27-32`) states the intent: "stack-agnostic worker
  container … Do not pre-guess every stack the project might ever use."

So the **direction is right**. The findings below are where the implementation
still fights it.

## 3. Flexibility limiters (ranked by impact on universal tasks)

### L1 — The four-zone layout is hard-enforced; new top-level files/dirs are impossible

- `sandbox.WRITABLE_ZONES = ("src","tests","docs","scripts")` (`sandbox.py:31`).
- `CLAUDE.md` Hard rule 1: work **exclusively** in those four dirs; everything
  else is EROFS.
- `declared_carveout()` (`stanok.py:493-530`) is the single gate for every
  declared path. For a **new top-level file** (`go.mod`, `package.json`,
  `Cargo.toml`) the ancestor climb is `dirname("go.mod") == ""` → the loop never
  runs → `None` → **launch rejected** (rc=13). Same for a **new top-level dir**
  (`internal/`, `cmd/`, `crates/`). The error text says it outright:
  `"... a NEW top-level file/dir has no safe rw carve-out"` (`stanok.py:609`).

Impact: a fresh Go/Rust/Node project cannot create its manifest or its idiomatic
directories. Today's workaround is "pre-create the file, then declare `edit:`".

### L2 — Tests are assumed to be separate files under `tests/`

- `run.sh` registry `test-glob` is matched as `tests/**/<glob>` (`run.sh:113`),
  smoke as `src/*.<ext>` (`run.sh:166`).
- `_protected_files()` = `tests/**` + `scripts/run.sh` (`stanok.py:835-855`) is
  the contract-lock / `:ro` protection set.

Impact: in-package tests (`*_test.go` beside the code, Rust `#[cfg(test)]`,
JS `__tests__/`) do not fit. Worse, a Go test placed under `src/` would be
**writable** by the machine (src is impl-rw) → the "tests are the immutable
contract" guarantee silently weakens for non-`tests/` stacks.

### L3 — "run exactly ONE test file" is a package-oriented contract

`run.sh test <path>` runs one file; `verify_gate` runs every file from
`list` in a `ThreadPoolExecutor(8)` (`stanok.py:789-794`), each spawning a fresh
`bash scripts/run.sh` → fresh `uv run`/`node` (60 s cap each, `run.sh:151`).
`go test ./...`, `cargo test`, `npm test` are package/crate-level, not per-file.

### L4 — Adding a stack touches 4–5 places, not "THREE"

`specs/STACKS.md` says three, `run.sh:41-42` echoes it. Reality:

1. `Dockerfile` runtime line (`:96-106`, `:135-137`);
2. `scripts/run.sh` `STACKS` line — a **6-field pipe-delimited heredoc**
   (`run.sh:58-60`), parser has no escaping and `|` is a separator;
3. `.claude/settings.stanok.json` `allowedDomains` (pypi/npm/deb today);
4. `CLAUDE.md` "Test forms" prose — a **fourth, drifting copy** of the registry;
5. image rebuild (`STANOK_DIGEST = sha256(Dockerfile+run.sh)`, `setup.sh:73`).

…plus `golang.org/x/...`, `proxy.golang.org`/`sum.golang.org` (Go),
`crates.io`/`static.crates.io` (Rust), `docker.io` (JVM/Gradle) as new domains.

### L5 — Documentation already drifts from the registry

`specs/STACKS.md` is stale: it documents a **5-field** registry line
(`<ext>|<glob>|<regex>|<test-runner>|<smoke-runner>`) while `run.sh` has **6**
(a `preflight` field was added); it lists only `js`+`py` though `run.sh` also has
`jq`, and its py runner is `python3` while `run.sh` uses
`uv run --no-project python3 -m pytest …`. This is the exact "грабля" the
operator wants removed: no check ties prose to the registry.

### L6 — Verdict-subversion protection is Python-only

`stanok.py:276-286` + rc=27 forbid `conftest.py`/`pytest.ini`/`tox.ini`/
`setup.cfg`/`pyproject.toml` under `tests/`. There is **no** analogous guard for
a `go`/`cargo` stack or for a `node` loader shim. The threat (a config that
rewrites an exit code) is language-agnostic; the mitigation is not. Note also
that a **legitimate** `pyproject.toml` (a modern pytest project) is blanket-
forbidden.

### L7 — cli.js is a patched monolith with no patch layer

31 commits / 12 hunks inside single lines of a 13 MB minified file;
`.git` = 362 MB, including two committed 13 MB backups. See CC-142…CC-145
(`specs/PLAN-cli-js-hygiene-2026-09-25.md`). Upstream is frozen, so the cost is
bounded, but the edits are unreviewable and unpinned against re-bundling.

### L8 — llama-server side is unmanaged

- The `tool_choice` object→`required` fix is a **loose `.patch`** in
  `~/git/grok-kimi/0001-llama-server-tool_choice-object.patch`, with no pinned
  llama.cpp commit, no build recipe, no verify — the same disease as L7.
- cli.js emits `<|think_off|>`/`<|think_on|>` markers (`oWK`/`aWK`/summarizer)
  that only mean something because `/data/models/chat_template.jinja`
  (qwen3.8-froggeric-v22.1, remote) interprets them. That coupling is
  **cross-host and undocumented in-repo**: cli.js and the template can drift
  independently.

## 4. Speed levers (measurable, low risk first)

| # | Lever | Evidence | Expected effect |
|---|---|---|---|
| S1 | One process per test file | `_run_one_test` → `bash scripts/run.sh test <f>` per file; `run.sh` spawns `uv run`/`node` per file | large suites pay interpreter+uv startup N times |
| S2 | Full suite re-run every turn | `verify_gate` lists **all** tests and runs them each turn (`:767-794`) | cost grows with suite size, not with the change |
| S3 | `uv run --no-project` inside the image | `run.sh:59`; image has system python + pytest | uv resolution per invocation; in-image could call `python3` directly |
| S4 | Single llama-server slot + KV eviction on supervisor turns | `CLAUDE.supervisor.md §3`, `PLAN-STANOK-REFACTOR.md:18` | serialization; each supervisor message evicts the machine's KV cache |
| S5 | Turn budget | `TURN_TIMEOUT_S=1800`, `API_TIMEOUT_S=600`, retries 2 (`stanok.py:54-55`, README) | correct as safety, not a speed win |

## 5. Maintainability smells

- **`CONTEXT.md` is 120 663 bytes** and is read at every supervisor session start
  (`CLAUDE.supervisor.md §1`). It grows per ticket; closed waves are never
  archived. This is the single biggest "понятнее/быстрее" item for the human
  loop (supervisor context, not the model).
- **~20 bespoke rc codes** (`0,1,2,6,7,13,15,16,17,20,21,22,24,25,26,27,28,124,143…`)
  across `run.sh`/`stanok.py`/`sandbox.py`, documented in three places
  (`run.sh:11-28`, `CLAUDE.md` rc table, README). A reason string in
  `summary.json` would be clearer than integers.
- `stanok.py` mixes zones, hidden-files gate, contract lock, SessionPlan, verdict,
  CLI parsing and Docker supervision in one 2032-line file.
- **Doc duplication**: registry semantics exist in `run.sh`, `CLAUDE.md`,
  `specs/STACKS.md`; rc semantics in `run.sh`, `CLAUDE.md`, README. Already drifting (L5).
- `evidence/` holds 49 run dirs in-repo; `.pytest_cache/` is present in the tree.

## 6. What NOT to change

The **harness** being Python is defensible and should not be "un-Pythoned":
`claude-agent-sdk` is Python-only, and the launcher is the operator's tool (not a
task). The flexibility problem is on the **task side** — L1/L2/L3/L4/L6 — not in
`stanok.py` being Python. (Merging these two is the main conceptual trap in the
request: "мы привязаны к питон и js" is true of *tasks*, not of *the станок*.)

## 7. Open questions for the operator

1. Canonical task layout: keep the 4 zones, or allow a per-ticket declared
   top-level allowlist (e.g. `impl: go.mod`, `impl: cmd/`)? (L1)
2. Test semantics: keep "one test file = one runner call", or add a whole-suite
   mode to `run.sh` (`run.sh test --all`)? (L3/S2)
3. Is a "bootstrap a new project" ticket allowed to create top-level files, and
   if so under what gate? (L1)
4. Do we invest in a **single stack manifest** (`stacks/<name>.toml` → generates
   registry + Dockerfile fragment + domains + docs)? (L4/L5)
5. llama.cpp: pin the build + move the `tool_choice` patch under version control
   with the rest? (L8)
6. Do we split/rotate `CONTEXT.md`? (S-5)
