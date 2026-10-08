# STACKS — adding a language stack to the machine

The machine is stack-agnostic by design: `scripts/run.sh` is the ONE fixed
contract (subcommands `test` / `smoke` / `list`), and the stack behind it is
data, not code. Adding a stack touches exactly THREE places:

## 1. `stanok/Dockerfile` — the runtime

Install the stack's runtime into the hermetic image (Node v22.22.3 comes from
the official nodejs.org tarball; python3 from the debian base). Anything the
stack's test runner needs (interpreters, compilers, package managers) is
baked in here — the image is hermetic, no host bind-mounts.

## 2. `stanok/scripts/run.sh` — ONE registry line

The `STACKS` variable is the single stack extension point: exactly ONE line
per stack, format

```
<ext>|<test-glob>|<name-regex>|<test-runner>|<smoke-runner>|<preflight>
```

- `test-glob` — `find(1) -name` glob for `list` (basename match);
- `name-regex` — ERE for the basename; validates `test`/`smoke` args (charset);
- `test-runner` — command line for `test` (timeout 60, stdin `</dev/null`);
- `smoke-runner` — command line for `smoke` (timeout 10, stdin `</dev/null`);
- `preflight` — cheap runner-availability probe (timeout 10, stdin
  `</dev/null`); a non-zero exit is ENV-FAIL (rc=6) — the runner is missing
  from the environment, NOT a red test.

The test-runner, smoke-runner, find-glob and the usage text are all
GENERATED from this registry — no other code change per stack. Current
registry (must match the live `STACKS` block in
`scripts/stacks.generated.sh`, generated from `scripts/stacks/*.toml` by
`scripts/gen_stacks.sh` — doctor `test_stacks_md_matches_registry`):

```
js|*.test.js|[A-Za-z0-9_-]+\.test\.js|node --test --test-force-exit|node|node --version
py|*_test.py|[A-Za-z0-9_-]+_test\.py|env PYTHONDONTWRITEBYTECODE=1 python3 -m pytest -q -p no:cacheprovider -o pythonpath=src|env PYTHONDONTWRITEBYTECODE=1 python3|env PYTHONDONTWRITEBYTECODE=1 python3 -m pytest --version
jq|*.json|[A-Za-z0-9_-]+\.json|jq empty|jq empty|command -v jq
```

SEC-01 path validation (strict charset, file exists, no symlink in any path
component, realpath containment in `tests/`) is stack-independent and lives
in `validate_path()` — it is NOT per-stack.

**Contract lock (P2):** `scripts/run.sh` is under `contract_lock` — a machine
run may modify it only if the ticket declares it in `declared_paths`
(runner-update ticket) or it did not exist at start (bootstrap). The
behavioral contract is pinned by
`launcher/tests_harness/test_runsh_contract.py` (20 hermetic tmpdir cases:
charset, realpath containment, timeout, `list` sorted-unique, rc=2 on
unknown extensions / wrong argument counts).

## 3. `stanok/.claude/settings.stanok.json` — network domains

`sandbox.network.allowedDomains` must cover the stack's package registries
so the machine can install its dependencies inside the bwrap sandbox
(currently: `pypi.org`, `files.pythonhosted.org` for Python;
`registry.npmjs.org` for Node; `deb.debian.org`, `security.debian.org` for
apt). A stack with no install needs adds nothing here.

## What does NOT change per stack

- `launcher/stanok.py` — the runner, verifier, contract lock, telemetry are
  stack-agnostic (they only call `scripts/run.sh`).
- `CLAUDE.md` (machine role) — "match the project's EXISTING stack" is
  stack-agnostic.
- The supervisor contract (tickets, evidence, rc codes) — unchanged.
