# SPEC-STANOK-SINGLE-TOML-PARSER (2026-09-26)

Supervisor-executed (launcher/scripts/tests_harness — infra, not the machine zone;
precedent CC-157..160). Closes backlog BL-2 + BL-3 (specs/STATUS.md).

## Background

The STACK REGISTRY manifests (`scripts/stacks/*.toml`, one per stack) are read by
TWO independent parsers:

1. `scripts/gen_stacks.sh:29-33` — a hand-rolled `sed` parser (6 keys:
   `ext|test_glob|name_regex|test_runner|smoke_runner|preflight`) that generates
   `scripts/stacks.generated.sh` (a single `STACKS='...'` assignment), sourced by
   `scripts/run.sh:65`.
2. `launcher/stanok.py:286-322` — `_verdict_config_patterns()` reads the SAME
   files via `tomllib` (the `verdict_config` key).

Nothing cross-checks the two. `gen_stacks.sh --check` is a manual command, not
wired into any test. The test suite validates the GENERATED file, not the
manifests (`test_doctor.py:164-183`), so the staleness class is open: edit a
manifest, forget to regenerate → all tests green, `run.sh` runs the stale
registry, tomllib consumers see the new manifests.

Live bug found while verifying (BL-3): `_stack_preflights()`
(`stanok.py:453-470`) regexes `^STACKS='(.*?)'$` against the SOURCE of
`scripts/run.sh` — but since CC-148 run.sh contains no literal `STACKS=` block
(it sources the generated file). The function therefore always returns `[]`,
so `preflight_image()` (doctor) runs ZERO per-stack runner probes — the
"runner available in the image" check (rc=16 ENV-FAIL class) is silently
disabled. The 4 tests in `test_launcher_preflight.py` never catch it because
they monkeypatch `_stack_preflights` itself.

## Design (agreed with the operator)

- ONE parser: `tomllib`. The manifests are the single source of truth.
- `scripts/run.sh` derives the registry at runtime: a `python3` heredoc
  (python3 is already a hard image dependency — the py stack's runner) reads
  `scripts/stacks/*.toml` sorted by filename and emits the same 6-field
  pipe-separated lines into the `STACKS` variable. The variable name and line
  format are UNCHANGED (all consumers use `<<< "$STACKS"` with `IFS='|'`).
  Fail-closed: missing required key / unparseable TOML / no manifests →
  non-zero exit (mirrors the old `gen_stacks.sh` exit 2).
- `launcher/stanok.py`: a shared tomllib manifest loader; `_stack_preflights()`
  reads the `preflight` key from the manifests (the regex over run.sh is
  deleted); `_verdict_config_patterns()` moves onto the shared loader (its
  fail-closed fallback to `_LEGACY_VERDICT_CONFIG` is preserved).
- Codegen deleted entirely: `scripts/gen_stacks.sh`,
  `scripts/stacks.generated.sh`, the `--check` mode.
- Image-provenance digest EXTENDED: `sha256(Dockerfile + scripts/run.sh +
  scripts/stacks/*.toml)` — the registry physically moves into the toml files,
  and run.sh becomes generic code identical regardless of manifest content;
  without the extension the digest would be blind to exactly the change class
  it was created for (a `preflight`/runner edit in a manifest). The
  concatenation order of the manifests is EXPLICITLY sorted by filename on BOTH
  sides (build-time `setup.sh`, doctor-side `_image_digest()`) — no reliance on
  shell-glob order. Docstrings/comments updated to name the new input set.
- The cross-check "both parsers see the same manifest" is closed BY
  CONSTRUCTION (one parser) + a new test that the REAL `_stack_preflights()`
  (no monkeypatch) equals an independent tomllib read of the live manifests.

## Change list

- `scripts/run.sh` — `source "$SCRIPT_DIR/stacks.generated.sh"` (:65) →
  python3+tomllib heredoc emitting `STACKS`; header comment (:62-64) rewritten.
- `launcher/stanok.py` — shared `_stack_manifests()` loader;
  `_stack_preflights()` from manifests; `_verdict_config_patterns()` on the
  shared loader; `_image_digest()` + sorted manifests, docstring updated;
  `preflight_image()` docstring (:487) updated.
- `setup.sh:83` — digest input + `$(ls "$DIR"/scripts/stacks/*.toml | sort)`,
  comment (:78-84) updated.
- `launcher/tests_harness/conftest.py` — `repo` fixture copies
  `scripts/stacks/` (the manifests) instead of `stacks.generated.sh`.
- `launcher/tests_harness/test_doctor.py` — `_registry_lines()` parses the
  toml manifests via tomllib (generated-file/run.sh fallback deleted);
  comment :48 updated.
- `launcher/tests_harness/test_launcher_preflight.py` — new test: real
  `_stack_preflights()` (no monkeypatch) == tomllib read of live manifests,
  non-empty.
- `README.md:118-120` — digest description updated to the new input set.
- Deleted: `scripts/gen_stacks.sh`, `scripts/stacks.generated.sh`.

## Acceptance criteria

1. `bash scripts/run.sh list` / `test` / `smoke` behave exactly as before on
   the live repo (the `test_runsh_*` suites pass on the updated fixture).
2. `launcher/tests_harness` hermetic suites pass: `test_runsh_*`,
   `test_wait_follow.py`, `test_launcher_preflight.py` (incl. the new
   no-monkeypatch test), `test_doctor.py` static checks.
3. `_stack_preflights()` returns the 3 live preflight commands (jq/node/pytest)
   — verified by the new test without monkeypatch.
4. `_image_digest()` and `setup.sh` compute byte-identical input
   (Dockerfile + run.sh + sorted manifests) — verified by re-computing both
   after the change and comparing.
5. `test_doctor.py::test_docker_image_digest_matches` FAILS until the image is
   rebuilt via `./setup.sh` (expected — the digest changed); the rebuild is a
   separate operator-confirmed step, NOT part of this change.
6. No references to `gen_stacks.sh` / `stacks.generated.sh` remain in
   `scripts/`, `launcher/`, `README.md`, `docs/`.
