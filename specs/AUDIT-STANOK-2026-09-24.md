# AUDIT — STANOK: native-first, KISS, multi-stack (2026-09-24)

Read-only audit, conducted by the supervisor against the pinned sources. Scope per mission:
filesystem/process boundary + developer ergonomics + stack agnosticism. No security deep-dive.
Line numbers are from the working tree at commit `6683d45` (submodule `bdfc7cf`).

Ground truth used: `stanok/launcher/stanok.py` (1852 lines), `stanok/launcher/sandbox.py` (118),
`stanok/scripts/run.sh` (226), `stanok/launch.sh`, `stanok/.claude/settings.stanok.json`,
`CLAUDE.supervisor.md`, `specs/REVIEW-KISS-CLI-FIRST-2026-09-24.md`,
`~/git/claude-code-2.1.88/cli.js`.

Settled and therefore NOT re-proposed: kill-list 1 (§3.1–3.4) and kill-list 2 (CC-125…130);
T2 burned (CC-131). T3–T5 are the deferred remainder of the SessionPlan plan.

---

## 1. THE BLOAT

| # | artifact (path:line) | LOC | incident it closes | replacement | verdict | conf |
|---|---|---|---|---|---|---|
| 1 | `NOISE_LINE_PATTERNS = ("node_modules/",)` + its filter in `_extract_smart_diff` (stanok.py:52-55, 558) | ~5 | none — a JS-era leftover (W10). The docstring directly above it (551-556) claims "No pattern heuristics"; the code contradicts the docstring | delete the filter; the raw tail is already the contract (§3.3) | **DELETE** | high |
| 2 | `scripts:` ghost header kind — `_FILE_LINE_RE` (73) = `impl\|test\|docs\|edit`; `_DECLARED_ZONES` (75) contains `scripts`; `SessionPlan.declared_paths` advertises `impl:/test:/docs:/scripts:` (96) | 0 (a lie) | none. A ticket line `scripts: x.sh` does not match → the header ends → rc=13 | pick one: add `scripts` to the regex, or drop it from (75)+(96) | **SIMPLIFY** | high |
| 3 | The writable-zone list is written out 5 times: `_DECLARED_ZONES` (75), `sandbox.DEFAULT_RW_ZONES` (sandbox.py:19), `hidden_files_gate` (207), `prepare_workspace` (516), `_tests_manifest` (700) | ~10 | CC-119/CC-125 (the quarantine/edit dance came from zone policy) | one constant, imported by all five consumers | **SIMPLIFY** | high |
| 4 | The launcher's own verdict dir is a writable mount: `evidence/` ∈ `DEFAULT_RW_ZONES` (sandbox.py:19, 63) and `label_paths` = `REPO_ROOT/evidence/<label>` (stanok.py:149-150) → the agent has rw over `.running` (1415), `launcher.stdout.log` (1414) and `summary.json` (1385, 1528) | — | the `.running` race already observed | keep evidence on the host only; do not pass it into the container | **DELETE** (the exposure) | high |
| 5 | create-vs-edit is a header claim nothing verifies: a pre-existing path declared as `test:`/`impl:` is quarantined (511-536) and then denied by the hook (897-924) | ~30 | CC-119 fire16 `rc=143`, retry1 1800 s stall | derive it from `os.path.exists` at parse time; a pre-existing path not marked `edit:` is a ticket defect (rc=13) | **SIMPLIFY** | high |
| 6 | Test discovery is layout-locked: `list` requires `tests/` (run.sh:187) and only `find tests` (190); the globs live in the registry (run.sh:58-60) | ~6 | none — a stack limit | let the registry declare the discovery root per stack, or document "tests must live under tests/" as a hard contract | **SIMPLIFY** | med |
| 7 | The 4-zone allowlist rejects every root file and every other dir (454-467): `go.mod`, `Cargo.toml`, `package.json`, `Makefile`, `internal/`, `cmd/`, `crates/` are all undeclarable | ~13 | none — blocks any non-Python/JS stack | zones = the top-level dirs of the declared paths; allow explicit root files | **SIMPLIFY** | high |
| 8 | `test_config_gate` (235-257) scans pytest config names only (`conftest.py`, `pytest.ini`, `tox.ini`, `setup.cfg`, `pyproject.toml`) | ~23 | a real one (conftest `pytest_sessionfinish` flips a failing test to rc=0) | KEEP — but it is the Python-shaped half of a rule the runner registry should own | **KEEP** | high |

Note on #6/#7: these two are the concrete answer to "any stack". Everything else in the machine
is already stack-neutral (`rc` only, `run.sh` is the sole entrypoint — `_run_one_test` 573-602,
`verify_gate` 623-628).

---

## 2. THE BOUNDARY (why the Python tripwires exist)

**Root cause: two policy layers with different granularity.**

- Mounts are **zone-level**: rw only `src/ tests/ docs/ scripts/ evidence/`, parent + `.git` ro
  (sandbox.py:19, 59-64).
- Ticket policy is **file-level**: `prepare_workspace` moves individual declared paths (527-536);
  the hook denies individual protected files (907).

Every Python tripwire in the launcher exists to re-impose a *file-level* rule on top of a *coarse*
mount. That is the crooked mechanism: the mount already grants rw over all of `tests/`, and the
hook then denies part of it in Python. Inside the container the agent does NOT have more freedom if
you delete the hook — it has the same zone-level freedom, minus the guard.

| Python-level restriction | mount / native equivalent | what must exist first | risk if removed TODAY |
|---|---|---|---|
| `_pretooluse_lock_hook` (897-924) deny Edit/Write on pre-existing `tests/**` | `:ro` bind of pre-existing test files + `:rw` bind of declared paths (Docker layers by specificity, already used at sandbox.py:59-63) | per-file rw derivation = **T4** | a pre-existing test can be rewritten; `_check_contract_lock` catches it only after the turn, and the violation list is cumulative (747-768) → the fix prompt cannot recover → one wasted turn, then a relaunch |
| `_check_contract_lock` (722-744) post-turn SHA diff | filesystem immutability makes it redundant | T4/T5 | none today — it is the second echelon that catches Bash-mediated writes the hook cannot see (882-885). KEEP as evidence (REVIEW Keep-list) |
| `_verifier_hook` (941-1036) PostToolUse RED feedback | already the native primitive (PostToolUse + `hookSpecificOutput.additionalContext`) | — | KEEP. Its only stack-ism: `tests_dir` (956) and `run.sh test` (966) |
| `sandbox_config_gate` (260-294) | native `sandbox.failIfUnavailable` (cli.js:8169) + the first Bash call | — | KEEP (CC-107: a non-existent deny entry EROFS-kills every Bash call) |
| `hidden_files_gate` (199-232) / `test_config_gate` (235-257) | none — cli.js does not know the project's runner | — | KEEP |

**Conclusion:** the only hook with a mount-level replacement is `_pretooluse_lock_hook`, and its
replacement requires T4. So the freedom goal is reached by *deriving mounts from the ticket*, not
by deleting hooks. Deleting the hook first is the trap: it removes the guard while keeping the
coarse mount — strictly worse.

---

## 3. THE CONTRACT (ticket ↔ sandbox)

**Current grammar (verified).** A ticket's leading block of `impl:|test:|docs:|edit:` lines plus an
optional `reset: none`; blank and `#` lines are skipped; the first other line ends the header
(470-508). Path rules: relative, no `..`, top-level dir ∈ {src,tests,docs,scripts}, not a bare zone
(454-467). `edit:` = modify in place, not quarantined (501-502, 527-529).

**Contradictions found (these are what the TUI can currently emit and break on):**

1. `scripts:` is advertised (75, 96) but unparseable (73) → rc=13 with a confusing message.
2. There is **no readonly vocabulary at all**. The sandbox cannot be derived from the ticket, so
   mounts are hardcoded (sandbox.py:19) and the Python hook bridges the gap. This is the direct
   cause of the operator's "the TUI gives bad tickets": the ticket cannot state read-only intent.
3. create-vs-edit is trusted, never checked against the filesystem (CC-119).
4. `evidence/` is writable but undeclarable — an invisible writable zone (sandbox.py:19 vs 75).
5. The effective contract (4 zones + 4 kinds) is stated nowhere the supervisor reads:
   `CLAUDE.supervisor.md` §1 names the ticket file but no header grammar.

**Proposed contract v2** (closed grammar, mounts derived before Claude Code starts):

```
# <title>
create: src/foo.py        # alias set: impl: | test: | docs:   — MUST NOT pre-exist
edit:   tests/bar_test.py # MUST pre-exist — rw, exempt from contract_lock
ro:     scripts/run.sh    # optional, MUST pre-exist — hashed as protected
reset:  none              # optional escape hatch (unchanged)
```

Rules: exactly one line per path, no duplicates; `create:`+`edit:` = the rw set; everything else =
ro; the zone list disappears (mounts come from the paths); a path/kind mismatch is rc=13 with the
offending line echoed. This makes `_validate_declared_path` (454-467) a pure shape check.

---

## 4. ACTION PLAN

| # | ticket | goal | evidence | verification | LOC |
|---|---|---|---|---|---|
| 1 | CC-132 | One source for zones/kinds: align `_FILE_LINE_RE`, `_DECLARED_ZONES`, `DEFAULT_RW_ZONES`, the four consumers | §1#2, §1#3, §1#7 | hermetic test in test_session_plan.py + `py_compile` + doctor | ~40 |
| 2 | CC-133 | Auto-detect create vs edit; a pre-existing path not marked `edit:` → rc=13 | §1#5, CC-119 traces | replay the CC-119 retry1 ticket → rc=13, no deny-loop | ~25 |
| 3 | CC-134 | Take `evidence/`, logs and the marker out of the container's rw view | §1#4 | e2e: `ls evidence/` inside the container fails; `summary.json` still written by the host | ~15 |
| 4 | CC-135 | **T4**: derive rw mounts from the plan (per-file, nearest existing parent) | §2, §3.2 | e2e: Bash EROFS on a non-declared file, RW on a declared one | ~60 |
| 5 | CC-136 | **T5**: delete `_pretooluse_lock_hook` (only after CC-135 is e2e-proven) | §2 | e2e: an attempt to rewrite a pre-existing test fails at the fs layer with a readable error | −28 |
| 6 | CC-137 | Delete the `node_modules` noise filter (make the docstring true) | §1#1 | doctor + a fixture whose tail contains a `node_modules/` line | −5 |

Order matters: 1→2→3 are independent; 4 gates 5. Items 1-3 are cheap and remove the contradictions
the TUI trips on today; 4-5 are the actual boundary move (the deferred T4/T5, now justified by the
"any stack / freedom inside the container" requirement rather than by a saved-run argument).

---

## Appendix A — UNVERIFIED / NEEDS A RUN

1. Can cli.js `deny` rules express "deny Edit on pre-existing tests only"? Not grepped yet.
   Verify: `grep -o 'Edit([^)]*)' ~/git/claude-code-2.1.88/cli.js | sort -u`.
2. Does `tools=CURATED_TOOLS` (1054) block anything the native sandbox would otherwise allow?
   Verify: a run with one extra tool and an audit of the resulting refusal.
3. `hidden_files_gate` reads only the top level of each zone (`os.listdir`, 212-218) — a hidden file
   in `src/pkg/` is invisible. Verify: fixture with `src/pkg/.secret`.
4. Can a Go/Rust runner be added without a Dockerfile change? The registry comment claims "runtime
   in the Dockerfile". Verify: add a line, run `docker run --rm <image> <preflight>`.
5. Interaction of `permission_mode="dontAsk"` (1050) with our deny hook and the native
   `PermissionRequest`/`PermissionDenied` events. Verify: one run with permission logging.

## Appendix B — DO NOT TOUCH (red team)

- **In-session retry loop** (`<verification_result>` + re-`query()`, 1039-1282). Red team: the host
  already re-runs `verify_gate`, so just relaunch. Rebuttal: KV-cache reuse inside one session is
  the whole point (99% hit rate), and 2.1.88 has no Stop-hook re-prompt primitive (CC-130) — a
  relaunch re-sends the entire prompt. KEEP.
- **`_verifier_hook`.** Red team: the model can run `run.sh test` itself. Rebuttal: it saves a turn
  and it is what prevents the CC-081 "fix the environment from src/" loop. KEEP.
- **`_stack_preflights`/`_image_digest`/`preflight_image` (353-431, ~80 LOC).** Red team: large, and
  not on the launch path. Rebuttal: CC-106 deliberately moved them to doctor; REVIEW §3.2 closed
  this exact item, and moving them again would be refactoring for its own sake. KEEP.
- **marker + flock + `status`/`stop` + turn watchdog.** No `--bg` in 2.1.88 → necessarily homegrown.
  KEEP.
- **`preflight_server` (326-350).** `n_ctx >= 123000` matches the effective native window exactly
  (CC-128). KEEP.
- **`hidden_files_gate` / `test_config_gate`.** Real exploits cli.js knows nothing about. KEEP.

No findings = nothing to report for: the summary.json contract, the rc namespace, `run.sh`'s rc
disjointness, the Docker hardening set (sandbox.py:92-104).
