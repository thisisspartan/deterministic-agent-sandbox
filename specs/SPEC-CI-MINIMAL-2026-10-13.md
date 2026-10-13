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
