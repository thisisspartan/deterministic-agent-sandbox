# REVIEW: LOOP-TRAP incident CC-204-retry3 (2026-10-07)

Status: FINDINGS ONLY — no code, ticket, or supervisor-file changes made.
Discussion participants: supervisor analysis + Red Team review. Both rounds
converged; the formulation in §4 is the agreed one, with two supervisor
nuances (§4.1.4, §4.2.3).

## 1. Incident (evidence)

- Run: `evidence/CC-204-retry3` (also `/tmp/stanok-logs/CC-204-retry3/`),
  session `c519cb0c-a974-4361-be08-6bc1ac3da749`, 182 Opik traces,
  rc=1, verifier FAIL, review DEFECT.
- Anatomy (verified against session jsonl):
  - Turn 2: **31 identical `Read` calls on `README.md`**, **32 word-for-word
    identical assistant text blocks** ("The contract_lock is a `:ro` file
    bind … Let me read the full contract_lock section in the README.").
  - loop-guard blocked the call **22 times** (at the 10th, 15th, 20th, 25th,
    31st repetition); the block text entered context as just another line and
    did not break the loop.
  - Turn 2 cost: 1584 s, 64 125 output tokens, live context 90 787,
    `prefix_break: true` — the loop was cemented in the KV cache
    (single continuous session, 94.9% cache hit).
  - Turn 3 died with `ECONNREFUSED`; run terminated, GPU not burning.
- Final verifier failure: `test_protected_tests_readonly` — append to
  `tests/smoke_math_test.py` SUCCEEDED (isolation gap).

## 2. Root cause (verified in code)

The ticket (retry3) declared `edit: tests/smoke_math_test.py`. The launcher
then **voluntarily dropped the file from the :ro bind list**:

- `launcher/stanok.py:702-704` — `for rel in _protected_files(): if rel in
  declared_set: continue`
- docstring `launcher/stanok.py:698-699` — "a DECLARED path is never bound
  (`edit:` on an existing test is exactly the case that must stay writable)".

The machine edited the file (1 Edit, turn 1), the file was writable, and the
isolation probe — which asserts pre-existing `tests/` files are read-only —
failed. The ticket created an unsatisfiable contract ("fix the test in
tests/" vs "tests/ is immutable, fix only from src/"); the 27B model latched
on it. The model is not at fault; the deadlock was designed by the ticket.

## 3. Rejected hypotheses (Red Team, accepted)

1. **"Escape through inode replacement" — WRONG.** `rename()` over an active
   mount point returns EBUSY; a per-file bind is not escapable while the file
   is mounted. The write succeeded only because the launcher removed the bind
   (§2), not because of a kernel hole.
2. **Directory-level `:ro` on `tests/` — REJECTED.** It would break the TDD
   pipeline: `test: tests/new_test.py` requires a rw carve-out on `tests/`
   (design pinned in `launcher/tests_harness/test_ro_protected_files.py:77-89`:
   dir carve-out + per-file :ro overlay over pre-existing tests).
3. **Raising sampling temperature — REJECTED.** temp>0 masks the deadlock
   (chaotic wandering burns the same budget) and greedy decoding
   (`--temp 0.0 --top-k 1`) is required for 27B codegen syntax. Fix at
   architecture level, not with randomness.
4. **Meta-rule in the system prompt — cosmetic.** A 27B model under context
   pressure will not self-arrest; the software must bound it.

## 4. Agreed formulation (to be sent as two tickets when the operator says go)

### 4.1 Ticket: launcher invariant (stanok.py / sandbox)

1. `edit:` on any path from `_protected_files()` (pre-existing `tests/**` or
   `scripts/run.sh`) → launcher fails closed **before container start**,
   rc=13 (`cannot edit pre-existing test/entrypoint`).
2. Remove the loophole `if rel in declared_set: continue` from
   `host_ro_paths` — all pre-existing protected files are ALWAYS :ro.
   New tests via `test: tests/new_test.py` remain creatable (rw carve-out +
   per-file :ro overlay — unchanged).
3. Supervisor pre-check (CLAUDE.supervisor.md §2): reject tickets with `edit:`
   on `tests/` or `scripts/run.sh`; editing an existing test is an operator
   host-side action before launch.
4. Nuance: `launcher/tests_harness/test_ro_protected_files.py:15` pins the
   behavior being removed ("`edit:`-declared files stay writable") — the
   ticket must delete/rewrite that pin (via test removal, not `edit:`, per
   the new rule itself).

### 4.2 Ticket: loop-guard circuit breaker

1. Detector: identical consecutive tool calls (same tool + same args).
2. At N=5: the hook stops warning and signals termination.
3. Nuance: the PreToolUse hook runs inside the container and cannot write the
   host `summary.json`; the signal (marker/exit code) must be consumed by the
   **launcher**, which writes `probe_result: "LOOP-TRAP"`, rc=1,
   verifier FAIL, and ends the run.
4. Supervisor protocol: `LOOP-TRAP` classifies as a ticket defect (B) —
   refine the ticket, do not re-run the same one.

## 5. Supervisor-side facts learned this session

- `scripts/run.sh` was found deleted on disk before the CC-204 launch (cause
  unknown); restored from `81c63a4` (commit `chore: restore scripts/run.sh`).
- CC-204 attempts: retry1 — infra (`TURN-1 API ERROR: Stream ended without
  receiving any events`); retry2 — real defect (`tests/smoke_math_test.py`
  stray `probe` token at line 48, NameError at collection); retry3 —
  the LOOP-TRAP incident above.
- Isolation probes (`tests/test_adversarial_test.py`) pass inside the sandbox
  (4/4 in retry2) and fail when run bare from the supervisor shell — expected,
  they are sandbox-bound probes, not code defects.
