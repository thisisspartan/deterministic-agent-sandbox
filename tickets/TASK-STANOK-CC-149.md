# TASK-STANOK-CC-149 — whole-suite mode: `run.sh test --all` (D4)

edit: scripts/run.sh
edit: tests/runsh_suite_test.py
edit: docs/stacks.md

`scripts/run.sh test <path>` runs exactly one test file; the external
verifier spawns one `bash scripts/run.sh test <file>` per file. This ticket
adds a whole-suite subcommand so a single invocation runs every declared
test — the contract a package-level runner (`go test ./...`, `cargo test`)
and the verifier's one-suite-call-per-turn both need.

## Contract: `bash scripts/run.sh test --all`

- `--all` is recognized ONLY as the sole argument to `test`:
  `test --all` → suite run. `test --all <anything-else>` or
  `test <path> --all` → rc=2 (refused, usage on stderr).
- The suite runs EVERY file that `list` would print (same discovery: the
  registry globs, sorted-unique, and the W12 unclaimed-test-like-file rule
  applies — an unclaimed file fails the suite with rc=1 exactly as it fails
  `list`).
- Each file runs with its own stack's test-runner, sequentially, with the
  SAME per-file timeout (60 s) and the same `=== <file> ===` header as the
  per-file `test` subcommand. A failing file does NOT stop the suite — all
  files run, and the rc is 1 if ANY file failed (runner 2/6 remapped to 1,
  exactly as in the per-file path).
- Preflight: each distinct preflight command runs once before the suite
  (same ENV-FAIL rc=6 semantics as the per-file path).
- Zero test files → rc=0, no output (an empty suite passes).
- rc table for `--all`: 0 all pass / 1 a test failed or unclaimed file /
  2 refused (arg shape) / 6 ENV-FAIL / 124 a file hit the 60 s timeout
  (the suite stops at the first timeout — a hung file would otherwise eat
  the whole budget).
- `smoke` and `list` are UNCHANGED. The per-file `test <path>` path is
  UNCHANGED (same rc semantics, same output).

## Deliverables

### 1. `scripts/run.sh` — the `test --all` branch

Implement the contract above. Keep the rc-table comment block at the top of
the file accurate (add the `--all` line if the block documents subcommands).

### 2. `tests/runsh_suite_test.py` — suite contract tests (pytest)

Hermetic: build a temp tree (tmp_path) with a copy of the live
`scripts/run.sh` + `scripts/stacks.generated.sh` + a `tests/` dir, and drive
`bash scripts/run.sh` via subprocess. At least these cases:
- `test --all` with one passing js file and one passing py file → rc=0,
  both `=== <file> ===` headers present, sorted order.
- `test --all` with one failing py file among passing ones → rc=1, the
  failing file's output present, the passing files still ran (headers
  present).
- `test --all` with zero test files → rc=0, empty stdout.
- `test --all extra` → rc=2; `test a.test.js --all` → rc=2.
- `test --all` with an unclaimed test-like file (e.g. `tests/zz_test.txt`)
  → rc=1 and the unclaimed file named on stderr.
- Per-file `test <path>` still works: one passing file → rc=0 (regression
  guard for the unchanged path).

### 3. `docs/stacks.md` — document the suite mode

Add a short section: `test --all` semantics (one invocation, all declared
tests, rc table as above) and that the per-file path is unchanged.

## Constraints

- No new dependencies; bash + coreutils only in run.sh.
- Do not change the per-file `test`, `smoke`, or `list` behavior.
- The generated registry block (`scripts/stacks.generated.sh`) and the
  manifests are UNCHANGED by this ticket.
- Scratch files only under `$TMPDIR`, deleted before you finish.

## Verification

```
bash scripts/run.sh test --all
bash scripts/run.sh test tests/runsh_suite_test.py
bash scripts/run.sh list
```

Final report (STRICTLY <= 5 lines):
1. TASK: DONE
2. Files: <files touched>
3. Tests: PASS
