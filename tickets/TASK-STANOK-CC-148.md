# TASK-STANOK-CC-148 — single stack manifest + generator (D2)

edit: scripts/run.sh
edit: tests/stacks_gen_test.py
edit: docs/stacks.md
edit: scripts/gen_stacks.sh
edit: scripts/stacks/jq.toml
edit: scripts/stacks/js.toml
edit: scripts/stacks/py.toml
edit: scripts/stacks.generated.sh
edit: scripts/stacks.generated/domains.json
edit: scripts/stacks.generated/runtime.list

The `STACKS` registry in `scripts/run.sh` is a 6-field pipe-delimited heredoc
hardcoded in the script. This ticket moves the registry data into one TOML
manifest per stack and a generator that emits the registry block, so that
adding a stack = editing ONE manifest + regenerating. The generated block
must be **byte-identical** to the current one — zero behavior change.

## Deliverables

### 1. `scripts/stacks/js.toml`, `scripts/stacks/py.toml`, `scripts/stacks/jq.toml`

One manifest per stack, exactly these keys (TOML):

```toml
ext = "js"
test_glob = "*.test.js"
name_regex = "[A-Za-z0-9_-]+\\.test\\.js"
test_runner = "node --test --test-force-exit"
smoke_runner = "node"
preflight = "node --version"
domains = ["registry.npmjs.org"]
runtime = ["node v22.22.3 (nodejs.org tarball, sha256-pinned in Dockerfile)"]
```

The `ext`/`test_glob`/`name_regex`/`test_runner`/`smoke_runner`/`preflight`
values for all three stacks MUST be exactly the current registry values
(reproduced in the "Current registry" section below). `domains`:
py = `["pypi.org", "files.pythonhosted.org"]`, js = `["registry.npmjs.org"]`,
jq = `[]`. `runtime`: one human-readable line per runtime package the stack
needs in the image (js: the node tarball; py: `python3`, `python3-venv`,
`uv` (pinned 0.5.24), `pytest`; jq: `jq`).

### 2. `scripts/gen_stacks.sh` — the generator

A bash script (bash + coreutils only; no new dependencies). It reads
`scripts/stacks/*.toml` (sorted by filename) and:

- **no args** — writes three generated files:
  - `scripts/stacks.generated.sh` — a bash file whose ONLY content is the
    `STACKS='...'` assignment (the 3 registry lines, one per stack, in
    manifest sort order: jq, js, py — see "Ordering" below).
  - `scripts/stacks.generated/domains.json` — a JSON array: the sorted
    union of all manifests' `domains` arrays.
  - `scripts/stacks.generated/runtime.list` — the `runtime` lines of all
    manifests, in manifest order, one per line.
- **`--check`** — regenerates all three in a temp dir and exits 0 iff they
  are byte-identical to the committed files, 1 otherwise (printing which
  file drifted). This is the verify hook the supervisor's doctor will call.

TOML parsing: the manifests use only strings and arrays of strings — parse
them with a small fixed parser (e.g. `sed`/`awk`), no external TOML library.

### 3. `scripts/run.sh` — consume the generated block

Replace the inline `STACKS='...'` heredoc with a source of the generated
file:

```bash
# STACK REGISTRY — GENERATED from scripts/stacks/*.toml by
# scripts/gen_stacks.sh. Do not edit by hand; edit the manifest and run
# `bash scripts/gen_stacks.sh`.
source "$SCRIPT_DIR/stacks.generated.sh"
```

Keep the existing comment block above it (the field-format documentation) —
it stays accurate. **Nothing else in run.sh changes**: the rc table,
`validate_path`, `stack_alts`, `usage`, `test`/`smoke`/`list` bodies, and the
W12 unclaimed-file rule all keep working because `$STACKS` holds the same
value.

### 4. `tests/stacks_gen_test.py` — generator contract tests (pytest)

At least these cases (build a temp tree with `tmp_path`, never touch the
real `scripts/`):
- `--check` exits 0 on the committed state (run against the real repo).
- `--check` exits 1 after tampering with a copy of a manifest (temp tree).
- The generated `STACKS` block equals the expected literal (the 3 lines
  below, in the order the generator emits).
- `domains.json` parses as JSON and equals the sorted union
  (`files.pythonhosted.org`, `pypi.org`, `registry.npmjs.org`).
- `runtime.list` has one line per runtime entry, in manifest order.

### 5. `docs/stacks.md` — how to add a stack

The manifest format (all keys), the generator usage (`bash
scripts/gen_stacks.sh`, `--check`), and the rule: the generated files are
committed and must never be edited by hand.

## Current registry (must be preserved byte-identically)

```
js|*.test.js|[A-Za-z0-9_-]+\.test\.js|node --test --test-force-exit|node|node --version
py|*_test.py|[A-Za-z0-9_-]+_test\.py|env PYTHONDONTWRITEBYTECODE=1 uv run --no-project python3 -m pytest -q -p no:cacheprovider -o pythonpath=src|env PYTHONDONTWRITEBYTECODE=1 uv run --no-project python3|env PYTHONDONTWRITEBYTECODE=1 uv run --no-project python3 -m pytest --version
jq|*.json|[A-Za-z0-9_-]+\.json|jq empty|jq empty|command -v jq
```

## Ordering

The generator emits stacks in **manifest filename sort order**
(`jq.toml`, `js.toml`, `py.toml`). The current heredoc is js, py, jq — the
line ORDER inside `STACKS` is behavior-irrelevant (run.sh matches each arg
against every line), so the generated block may differ from the old heredoc
in line order but each of the 3 lines must be byte-identical to the
corresponding line above. Your test in deliverable 4 must assert the
generated block equals the 3 lines above **as a set of lines** (order per
the generator's sort rule).

## State from the previous attempt (retry1)

`tests/stacks_gen_test.py` and `docs/stacks.md` already exist and are
correct — do NOT rewrite them. What is missing: the three manifests,
`scripts/gen_stacks.sh`, the three generated files, and the `run.sh` edit.
The previous run died before creating them (the tests failed because
`gen_stacks.sh` did not exist).

## Constraints

- No new dependencies; bash + coreutils + the existing python3/pytest for
  the tests.
- Do not change `run.sh` rc semantics, path validation, or subcommands.
- The generated files are committed artifacts (the machine commits nothing —
  the supervisor commits after the run; just leave them in the tree).
- Scratch files only under `$TMPDIR`, deleted before you finish.

## Verification

```
bash scripts/gen_stacks.sh --check
bash scripts/run.sh list
bash scripts/run.sh test tests/stacks_gen_test.py
bash scripts/run.sh test tests/smoke.test.js
bash scripts/run.sh test tests/wordfreq_test.py
```

Final report (STRICTLY <= 5 lines):
1. TASK: DONE
2. Files: <files touched>
3. Tests: PASS
