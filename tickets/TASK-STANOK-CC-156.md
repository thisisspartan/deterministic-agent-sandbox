# TASK-STANOK-CC-156 — restore the pinned py interpreter on the host + measure `test --all`

Supervisor-executed. Follow-up to CC-152 (`f29201c`/`1af0b15`) and CC-149
(`3ce9c4d`/`ef054e8`).

## Incident / context

**1. Host/container divergence (CC-152).** The py runner changed from
`env … uv run --no-project python3 -m pytest …` to
`env PYTHONDONTWRITEBYTECODE=1 python3 -m pytest …` (`scripts/stacks/py.toml`).
In the image this is the system python carrying the **pinned pytest 8.3.3**
(`Dockerfile` / `requirements.txt`). On the **host**, `python3` is the system
interpreter with **pytest 9.1.1** — and `launcher/tests_harness/conftest.py`
was changed to drop the `VIRTUAL_ENV` pointing that used to make `uv run` use
the repo `.venv` (8.3.3). So the harness now tests the py stack under a
different runner version on the host than the machine gets, and the test was
adapted to the new behavior rather than the environment being pinned.

**2. The CC-149 speed claim is unmeasured.** `verify_gate` was switched from N
per-file spawns (8-way `ThreadPoolExecutor`) to ONE **sequential**
`run.sh test --all` (`_run_suite`). The stated win (S1/S2: one `bash+run.sh`
startup instead of N) is real, but the change also **removes the 8-way
parallelism**: for a suite of many small files it can be slower. The
"~2.20s → ~2.00s" figure in `STATUS.md` belongs to CC-152 (the `uv` drop), not
to CC-149.

## Change

- **Pin the host interpreter** for the py runner again — e.g. keep `uv run`
  (or an explicit `.venv/bin/python`) on the host, or document the divergence
  as intentional. Do not silently run the host under an unpinned pytest.
- **Measure `test --all` vs the old parallel path** on a real multi-file suite
  (generate ~20 trivial `*_test.py`/`*.test.js` files in a scratch repo), 3
  runs each; record wall time in `specs/STATUS.md`.
- If `test --all` is slower: either parallelize inside `run.sh` (bounded, same
  rc semantics) or revert `verify_gate` to the per-file spawn primitive
  (`_run_one_test` is kept — the rc=2 fallback already uses it).

## Verification

- Recorded before/after wall times on the same machine and suite size.
- rc table unchanged: `test_runsh_runner_pins.py` + `test_runsh_contract.py`
  green; `test_verdict_safety.py` green.
- `bash hooks/doctor.sh` green (host side; the image digest gate aside).
- A machine smoke on a py ticket still ends rc=0 / verifier=PASS.

## Non-goals

- No change to the `run.sh` subcommand surface or rc table.
- No new stack.
