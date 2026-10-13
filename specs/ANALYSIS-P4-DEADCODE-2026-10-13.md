# ANALYSIS-P4 — dead-code audit of `stanok/` (machine directory, launcher)

Date: 2026-10-13. Research only: no code was edited or deleted. Base SHA:
`fdf83ff` (stanok main, clean tree) — line numbers cite that commit; a later
audit must re-state its base SHA (operator note 2026-10-13: line numbers drift
between local copies and published code). Method and limits are stated first,
because two mechanical scanning passes produced false positives AND false
negatives that a human check corrected (§5).

Scope: `launcher/*.py` (17 modules), `launcher/tests_harness/` (consumer evidence
only), `launcher/__pycache__/**`, entry-point scripts (`launch.sh`, `setup.sh`,
`hooks/doctor.sh`, `infra/netpol-smoke.sh`, `k8s/*.tmpl`). Out of scope per the
brief: `requirements.txt` (`image-requirements.lock`) and `scripts/stacks/*.toml`
judgments. Test files themselves are never "dead code" — they are reachability
evidence.

---

## 1. Entry points and the reachability graph (grounded)

Static anchors (verified in this tree):

1. `launch.sh:30` → `launcher/stanok.py` (thin shim, execs `launcher.cli.main`)
   → `cli.main()` (cli.py:635). `cli.py:23-42` imports config, exitcodes, gates,
   k8s, logs, opik, plan, session, summary, ticket, `stanok` (used for
   `stanok.__file__` in the child self-spawn, cli.py:372).
2. Host dispatch (cli.py:673-718): `in_container`/`no_sandbox` env reads at
   cli.py:673-674; in-process branch cli.py:691-709 (`cmd_run`); host k8s branch
   cli.py:718 `k8s.host_launch_k8s` (the "run/status/wait/stop" branches at
   640-645; `STANOK_RUNTIME=docker` refused at 714-717). `main()` never calls
   `cli._runtime_mode()` — see §3 B1.
3. Pod side: `k8s/worker-job.yaml.tmpl` runs `/stanok/runner/pod_runner.py`;
   `pod_runner.main()` (pod_runner.py:41) unpacks the payload, then
   pod_runner.py:131-133 execs `launcher/stanok.py run` with
   `STANOK_IN_CONTAINER=1` — i.e. the Pod re-enterers `cli.main()` in-container.
   So every module except `netpol.py` and `pod_runner.py` is reachable through
   `cli.main`; `k8s.py` additionally imports gates/opik/verify (k8s.py:61) and
   lazily `cli._early_abort` (k8s.py:746, used at 759-828); `session.py`
   imports verify + gates.context_rot_threshold (session.py:23-24); `ticket.py`
   imports verify._protected_files (ticket.py:16); `zones.py` is consumed by
   gates and ticket.
4. Doctor: `hooks/doctor.sh` is `uv run --directory <repo> pytest
   launcher/tests_harness/` — the doctor check IS the test suite.
   `test_doctor.py:122` calls `gates.preflight_image` — the only runtime
   consumer of that gate (§3 B2).
5. `infra/netpol-smoke.sh:97/119` — `$PY -m launcher.netpol` renders and
   applies the NetworkPolicy, the only production consumer of `netpol.py`.

Reachability verdict: all 17 modules are reachable from ≥1 entry point. Dead code
could therefore only live *inside* modules, at member level — searched below.

## 2. Category (a) — fully dead (no caller, no test, no doc anywhere): NONE

The final mechanical sweep (every `def`/`class` in `launcher/*.py`, counting
word occurrences across all .py and requiring "mentioned only on its own
def/class line" to count as dead) returned an EMPTY list. There is no production
member in `launcher/` with zero references anywhere. This is the headline result
of the audit and is worth stating plainly: the CC-258 Docker-path removal left
no orphaned functions in `src`.

Supporting spot-checks (all members presumed suspect by earlier drafts, all
verified ALIVE):

| Member | Call site proving it live |
|---|---|
| `k8s.scratch_contract_violations` (k8s.py:258) | k8s.py:981 (host contract recompute) |
| `session._post_turn_decision` (session.py:598) | session.py:982 (verdict pipeline in the turn loop) |
| `cli._read_ticket_contract` (cli.py:113) | cli.py:189 (cmd_run) |
| `cli._fail_early` (cli.py:58) | cli.py:192, 196-200, 213, 217 (cmd_run refusal paths) |
| `cli._runtime_mode`... no — | see §3 B1 (test-only) |
| `Config.api_timeout_ms` (config.py:102) | session.py:120 (`API_TIMEOUT_MS` env) |
| `Config.claude_bin` | session.py:696 (`cli_path=`) |
| `Config.max_agent_turns` | session.py:715 (`max_turns=`) |
| `Config.api_timeout_s` | internal-only, but live: feeds `api_timeout_ms` (config.py:103) and the turn-timeout adjustment (config.py:81) |
| all `ExitCode` members | 1-13 prod refs each (DEFECT 4, ENV_FAIL 13, …); none unreachable |
| `netpol.model_ip/netpol_variables/canonical/revision/render_*` | full chain reachable from netpol `__main__` (netpol.py:93-94) via netpol-smoke.sh |
| `ticket.*`, `verify.*`, `summary.*`, `zones.*`, `plan.SessionPlan`, `logs.log` | multi-caller; no orphan members found |

## 3. Category (b) — referenced ONLY by test code

### B1. `cli._runtime_mode()` — cli.py:625-632 — the audit's real finding

- Production callers: ZERO. `main()` (cli.py:635-718) performs the dispatch
  itself: `STANOK_IN_CONTAINER` / `STANOK_NO_SANDBOX` env reads at 673-674,
  branch at 691, k8s fallthrough at 711-718. No code anywhere else names it.
- Its only consumers: its own test — `test_k8s_wiring.py:50,52` (`assert
  cli._runtime_mode() == "k8s"` for every env value) plus that file's
  docstring (lines 4, 9, 46). The function's own docstring justifies keeping it
  as "the dispatch stays testable without a cluster" — but the dispatch it
  claims to provide no longer goes through it.
- Its only non-test mentions are PROSE: `ARCHITECTURE.md:14` ("`cli._runtime_mode()`
  is a constant `\"k8s\"`") and `ARCHITECTURE.md:57` ("-> dispatch
  (cli._runtime_mode — always k8s, CC-258)"). The architecture document routes
  through a function the code no longer calls.
- Classification: (b) test-only member + (c) doc drift, simultaneously. A test
  that asserts a constant returns a constant is self-confirming: deleting B1
  would force deleting its 2 test assertions and rewriting 2 ARCHITECTURE lines;
  keeping it costs one indirection the real dispatch does not use. Do NOT call
  it "dead — delete it": the honest statement is that the documented dispatch
  contract and the code have diverged, and only the self-test holds the function
  up.

### B2. `gates.preflight_image` cluster — gates.py:345-438 — live-by-construction: the doctor IS its caller

Cluster: `preflight_image` (gates.py:390), `_image_digest` (gates.py:373),
`_stack_preflights` (gates.py:345), `DIGEST_INPUTS` (gates.py:370).

- Production callers: ZERO (nothing imports or calls `preflight_image`;
  cli.py:28-32 deliberately does not import it). Its only invocations:
  `test_launcher_preflight.py:83,92,103,116` and `test_doctor.py:122`
  ("preflight_image the launcher uses — no second shell implementation").
- But the doctor (`hooks/doctor.sh` = `pytest launcher/tests_harness/`) is an
  operational entry point: these tests are how the image-digest check runs. The
  docstring makes the design explicit: "CC-106: no longer on the launch path …
  doctor calls it (test_doctor.py::test_docker_image_digest_matches)"
  (gates.py:398-399).
- Structural risk: the cluster is reachable only through a test. Delete or break
  `test_doctor.py::test_docker_image_digest_matches` or the four
  `test_launcher_preflight.py` units and the whole cluster (including the
  `DIGEST_INPUTS` tuple and the `stanok.digest` LABEL contract setup.sh bakes)
  becomes dead code on the spot, with no gate failing at launch.
- k8s-era replacement is live and separate: `k8s._preflight_image_label`
  (k8s.py:586, invoked by `_preflight`'s check list k8s.py:689) — the k8s
  runtime check for image staleness. So `preflight_image` is now the
  docker-runtime-era half of the image check, preserved for docker builds the
  host no longer launches: its `docker inspect`/`docker run` body (gates.py:408,
  427) only makes sense against the host's docker, which exists solely for
  `setup.sh`'s build/push step.
- Classification: keep (intentional per CC-106; the "doctor = pytest" design is
  the operating contract), but flag it: it is the most fragile live code in the
  package — reachable only via the test suite, and its body is a Docker-path
  probe surviving the Docker-path removal.

## 4. Category (c) — referenced only in comments/docs (stale prose)

C1. `ARCHITECTURE.md:14` + `:57` — routes launch flow through
    `cli._runtime_mode` (see B1). The prose flow is otherwise accurate about
    outcomes (ENV-FAIL for `STANOK_RUNTIME=docker`, k8s fallthrough); only the
    attribution is stale.

C2. `gates.py:4` — module docstring lists "sandbox-config, the server/image
    preflights" as its gates. No sandbox-config gate exists in gates.py (grep
    finds nothing); `test_sandbox_config_gate.py` was itself deleted with the
    Docker path (its orphan bytecode, §6).

C3. `cli.py:86` in `_open_run_state` docstring: "only a fresh in-process run
    (no-sandbox) writes its own [marker]" — describes the live `STANOK_NO_SANDBOX`
    mode correctly, but uses the retired vocabulary (no sandbox exists in the
    k8s runtime; see §5).

C4. `cli.py:345` comment "the former launch.sh + sandbox-run.sh, in Python".
    `sandbox-run.sh` does not exist anywhere in the repo (verified). Historical
    marker, harmless but references a deleted artifact.

C5. `k8s.py:17` "The verdict stays host-issued with the same priority as the
    Docker path", `k8s.py:261` ("…as the Docker path (the two cannot drift)"),
    `k8s.py:883` ("same semantics as the Docker path's no-summary case") —
    three normative comparisons to a removed runtime. The behavior contract
    itself is real; the comparison anchor is gone.

C6. `k8s.py:591` — `_preflight_image_label` context names "this to doctor for
    the Docker path; the operator preflight spec (2026-10-12)" — accurate
    history but implies the docker-era half (B2) without saying so.

C7. `gates.py:139` / `ticket.py:42` — cross-references to
    `test_docker_bind_resolves_symlink_source`. VERIFIED STILL PRESENT
    (`test_ticket_zone.py:225` defines it): these references are live and do NOT
    belong in the stale list; they only look stale because of the Docker name.

C8. Test-file docstrings referencing removed machinery (comments only, no
    behavioral claims): `test_ro_protected_files.py:9`,
    `test_evidence_boundary.py:23`, `test_stage3_src_tree.py:21`,
    `test_stage3_tests_tree.py:21`, `test_session_plan.py:11`,
    `test_ticket_zone.py:11-23` header. Historical prose about the deleted
    `sandbox.py` / `run_sandboxed` mock harnesses / removed `sandbox_argv`
    mount-table tests.

Out-of-scope historical documents that still describe deleted paths as present
(`specs/NOTE-SANDBOX-BARRIER-2026-10-08.md` cites `sandbox.py:105-106,137`;
`specs/REVIEW-KISS-CLI-FIRST-2026-09-24.md`, `specs/PLAN-AUDIT-2026-10-08.md`
discuss `preflight_image` status) are archive records, left untouched.

## 5. CC-258 Docker-path remnants — explicit check (the brief's focus)

- `sandbox.py`: ABSENT — grep finds no `import ... sandbox`, no `sandbox.`
  attribute use, no `run_sandboxed`, no `sandbox_argv` in any .py or shell
  script except §4 C8 prose. Its former content was moved to `zones.py`
  (acknowledged in `zones.py:2` and `test_session_plan.py:11`). The module
  removal is COMPLETE at source level; only bytecode debris remains (§6).
- Runtime dispatch remnants: `STANOK_RUNTIME=docker` refusal (cli.py:714-717)
  and `test_k8s_wiring.py`'s constant-assertion cluster are the only
  "dispatch" left; B1 covers this precisely — the named dispatch function is in
  the (b) set while the real dispatch inlines the env reads.
- `STANOK_NO_SANDBOX` (cli.py:673-674, 691-709): a LIVE host mode (the in-process
  test/verification run used by `test_doctor.py`, `test_worktree.py`), not dead
  code. Named after the deleted sandbox, retained semantics. Keep; note the name.
- `launch_background` / `k8s.host_launch_k8s` / marker protocol / pod re-entry:
  all live, no orphan members.
- Conclusion: the Docker-path deletion left prose remnants, bytecode debris and
  one test-only function (B1); no orphaned live-branch code.

## 6. Filesystem debris — orphan byte-code (not code; cleanup inventory)

.pyc files whose source no longer exists (verified by name-mapping over
`launcher/__pycache__/**`, `tests_harness/__pycache__/**`):

- `launcher/__pycache__/sandbox.cpython-312.pyc`, `sandbox.cpython-313.pyc` ←
  deleted `launcher/sandbox.py`
- `tests_harness/__pycache__/test_sandbox_config_gate...pyc` (C2's gate test)
- `tests_harness/__pycache__/test_tmp_bind...pyc`, `test_t4_mounts...pyc`,
  `test_network_preflight...pyc` (deleted Docker-mount tests)
- `tests_harness/__pycache__/test_stage3_fresh_verify...pyc`,
  `test_stage3_worker_lifecycle...pyc`, `test_k8s_pod_settings...pyc` (tests
  folded into the k8s suite)

9 files total. They are not in the `list`-gate violation space (immediate-parent
`__pycache__` exemption) but they are the physical shadow of everything CC-258
deleted, and they mislead auditors (a grep over the tree hits them).

## 7. Category (d) — ambiguous / keep

D1. `launcher/netpol.py` (whole module): no production importer. Reached only
    via `python3 -m launcher.netpol` (infra/netpol-smoke.sh:97) and its tests.
    Its docstring names the intended second consumer as future: "and the
    launcher, for a future apply-at-startup" (netpol.py:21-23). No member of it
    is dead (all chain to `__main__`). Keep as live infra tooling; do not let a
    naive reachability-from-launch scan retire it.
D2. B2 cluster (`preflight_image` + helpers): keep, with the fragility note of
    §3 B2 — recommend an explicit "this is the doctor's implementation, guard
    its test" banner if any future cleanup touches `test_doctor.py`.
D3. `STANOK_NO_SANDBOX` knob and `summary.py:330`/`config.py:10` prose: live
    behavior with retired naming. Keep.
D4. `k8s.py`'s lazy `from launcher.cli import _early_abort` (k8s.py:746): a
    deliberate cycle-avoidance import with six real uses (759-828). Keep.
D5. `image-requirements.lock` / `scripts/stacks/*.toml`: out of scope per the
    brief; noted only insofar as B2 (`DIGEST_INPUTS`) pins their content into
    the image digest contract, so they are inputs to a live check, not
    unjudged dead files.

## 8. Method notes and false-positive traps (for the next phase)

Two mechanical scans were run and BOTH must not be used raw:

- Naive "define-and-search `<name>(` word-grep" passes (the ones a quick audit
  script produces) falsely flagged `k8s.scratch_contract_violations`,
  `session._post_turn_decision`, `cli._fail_early`, `cli._read_ticket_contract`,
  `config.api_timeout_ms` as dead — every multi-line call (`name(\n  args`) and
  attribute call (`cfg.field`) defeats `name(` grep. All five were manually
  confirmed LIVE (§2 table). A future bulk cleanup must not act on such lists.
- The reverse direction: name-mentions in docstrings inflate "used" counts — a
  member referenced only in prose passes a presence filter while being
  functionally dead. The §4 list is exactly that set, and it was assembled by
  reading every flagged site, not by counting hits.
- The zero-reference sweep (§2) is the authoritative dead-member scan: it
  produced an empty list; categories (b)-(d) were then built by per-site
  manual verification of every function a coarser scan flagged
  (`_runtime_mode`, `preflight_image`, plus the §2 false positives).

## 9. Verdict summary

- Modules: 17/17 reachable. Members: 0 fully dead.
- (a) fully dead: 0.
- (b) test-only: 1 real (`cli._runtime_mode`, cli.py:625) + 1 intentional
  doctor-only cluster (`preflight_image` et al., gates.py:345-438).
- (c) stale prose in live files: 8 sites (C1-C8; one candidate, C7, verified as
  NOT stale).
- (d) ambiguous/keep: 5 (D1-D5) + 9 orphan bytecode files.
- CC-258 state: source-level removal complete; residue is prose, bytecode, and
  the test-only `STANOK_RUNTIME`-era vocabulary.
