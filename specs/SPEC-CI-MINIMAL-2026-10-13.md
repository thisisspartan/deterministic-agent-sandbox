# SPEC-CI-MINIMAL (2026-10-13) — harness CI without cluster/docker/jq

Origin: operator decision after the P5+P6 wave (2026-10-13). The harness
(`launcher/tests_harness/`, 433 tests) must run green on a bare CI runner:
no k8s cluster, no docker daemon/image, no jq, no repo `.venv`. CI does NOT
protect the launch path (`preflight_image` stays out of the launch path —
behavior change, not protection); it protects the harness contract itself.

## Requirements

1. **Skip-guards, not test-subset selection.** Every environment-dependent
   probe skips with an explicit reason when its tool is absent
   (`shutil.which(...) is None`): docker ×4 (`test_docker_available`,
   `test_machine_image_built`, `test_docker_image_digest_matches`, and
   `test_docker_bind_resolves_symlink_source` in `test_ticket_zone.py` —
   a PRE-EXISTING guard found during the bare run, enumeration corrected),
   jq ×2 (`test_test_json_valid_passes`, `test_test_json_invalid_fails`),
   kubectl (`test_kubectl_available`; `test_k8s_cluster_nodes_ready` already
   had the which-skip). A skip is a valid refusal (same semantics as the
   rc=21/22 skips), never a silent removal of a test.
2. **Guard-test defect fix (operator-found 2026-10-13).**
   `test_supervisor_zone_not_published` passed VACUOUSLY when the parent repo
   was absent: `git ls-files` in a non-repo returns rc=128 with empty stdout
   → `assert not tracked` green while checking nothing. Required:
   - parent authenticity via `git rev-parse --git-dir` + `.gitmodules`
     naming the `stanok` submodule;
   - outside the published-parent layout → skip with reason ("absent" /
     "not-parent");
   - inside the layout → `git ls-files` rc≠0 is a FAIL, never an empty list.
3. **All `REPO_ROOT.parent` readers enumerated** (complete list, 2026-10-13):
   `test_doctor.py` `_supervisor_zone_present` (helper, skip-safe),
   `test_context_md_budget` (skip-safe), `test_supervisor_zone_not_published`
   (fixed by R2), `test_stacks_md_matches_registry` (was a
   FileNotFoundError crash outside the parent layout → now skip-with-reason);
   `test_timer_contract.py` `SUPERVISOR_PROTOCOL` (already skip-safe).
4. **Expected bare-run counts** (parent checkout + stanok submodule, deps
   installed into the CI python — no repo `.venv`, PATH without
   docker/jq/kubectl): **423 passed, exactly 10 skipped, 0 failed**
   (measured 2026-10-13, `/tmp/ci-layout` run). The 10:
   `test_context_md_budget`, `test_kubectl_available`,
   `test_k8s_cluster_nodes_ready` (supervisor zone absent in a fresh clone),
   `test_I6_host_interpreter_is_pinned` (no repo `.venv`),
   docker ×4, jq ×2. The original plan said 9 (docker ×3) — the bare run
   found the 4th docker probe (`test_ticket_zone.py:224`, pre-existing
   guard); the count follows the code, not the plan.
   `specs/STACKS.md` and `CLAUDE.supervisor.md` ARE
   tracked in the parent → their tests RUN (not skip) in parent CI.
5. **Workflow `.github/workflows/harness.yml` in the PARENT repo**
   (the guard needs the parent layout; a stanok-only CI cannot run it):
   checkout with submodules → setup-python 3.11 → `pip install -r
   stanok/image-requirements.lock` (pip-native: uv-compiled, sha256-hashed)
   → run pytest with a PATH filtered of docker/jq/kubectl → assert rc=0 AND
   exactly 10 skipped. A changed skip count (up OR down) fails CI.
6. **Contract hardening (operator review 2026-10-13).** The count alone can be
   satisfied by a substitution (one skip out, another in); the contract is now
   the exact SET of skipped tests: pytest runs with `-rs`, the workflow
   extracts the short-summary locations (`file:line`, relative to `stanok/`)
   and diffs them against `.github/ci-expected-skips.txt` (10 identifiers,
   measured in the bare parent layout); the count check is kept as secondary.
   Runner pinned to `ubuntu-24.04` (`ubuntu-latest` moves to Ubuntu 26 on
   2026-10-19 — the skip set must not drift under the contract);
   `actions/checkout@v7` + `actions/setup-python@v7` (both `node24` runtimes,
   verified in their `action.yml`); explicit preflight step
   `python3 -m pytest --version` (the run.sh tests call `python3 -m pytest` —
   a missing pytest must fail loudly before the suite, not as 9 runner
   failures).

## Layout verification (measured 2026-10-13)

- Parent layout (`/tmp/ci-layout`: parent clone + stanok submodule at
  `4a8c789`, python 3.11 venv from `image-requirements.lock`, PATH farm
  without docker/jq/kubectl): **423 passed, 10 skipped, 0 failed**; the
  guard test RUNS and PASSES there (state "present").
- Standalone stanok checkout (`/tmp/ci-solo`): guard SKIPS with reason
  "no parent repo at REPO_ROOT.parent" — no vacuous pass.
- Foreign git parent (`/tmp/ci-notparent`: git repo, no `stanok` in
  `.gitmodules`): guard SKIPS with reason "not this project's parent".
- Local full harness with all tools present: 433 passed, 0 failed (no
  regression from the guards).
- Actions run `38400431043` (job log): `423 passed, 10 skipped in 32.50s`,
  `pytest rc=0`, `skipped=10 (expected exactly 10)` — the runner count matches
  the contract.
- Operator reproduction reconciliation (2026-10-13): the operator's bare run
  gave 424/9 — the one-test delta is `test_runsh_py_stack.py:66`
  (`test_I6_host_interpreter_is_pinned`): the operator's sandbox created a
  repo `.venv` symlink (so I6 runs and passes); the CI layout has no repo
  `.venv` (deps go to the setup-python interpreter), so I6 skips — the 10th.
  The full 10-skip set (captured with `-rs` in the same layout):
  `test_doctor.py:118/123/131` (docker), `test_doctor.py:156/169` (kubectl —
  zone-absent skip fires before the which-check), `test_doctor.py:276`
  (CONTEXT.md absent), `test_runsh_contract.py:195/205` (jq),
  `test_runsh_py_stack.py:66` (no repo .venv), `test_ticket_zone.py:224`
  (docker, pre-existing guard).
6. **Division (operator 2026-10-13):** agent — R1..R5 implementation,
   bare-run proof, publication (origin+github), RA-3 closure record,
   STATUS.md section, link to a green Actions run. Operator — fresh clone,
   repeat of the workflow commands bare, guard must skip-with-reason in a
   simulated CI layout, count 424/9, workflow vs `image-requirements.lock`
   review. Human — confirms publication.

## Out of scope

- No cluster/docker/jq dependency in CI; no `preflight_image` in the launch
  path; no CI for the machine runtime itself (the k8s path is proven by
  real runs + evidence, not by CI).
