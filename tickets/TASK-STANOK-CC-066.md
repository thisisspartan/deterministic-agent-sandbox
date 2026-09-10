# TASK-STANOK-CC-066 — Harness diagnostics: CONTEXT-ROT metric + read-guard repo root

## Executor
**Supervisor, NOT the machine.** The machine cannot edit `launcher/stanok.py` or
`hooks/read-guard.sh` (read-guard denies `hooks/`; bash-gate allows only
`run.sh`; `hooks/` is `denyWrite`). Execute in the control-room session.

## Background

Two harness defects surfaced in the cc064 run (`tickets/TASK-STANOK-CC-064.md`,
label `cc064-fire-heat-inertia`). Both are noise/UX of the harness — neither
broke the run (rc=0, verifier=PASS), but both waste model turns and train the
operator to ignore the logs.

---

## Part A — CONTEXT-ROT metric reports a nonsense number

### Observed
`evidence/cc064-fire-heat-inertia/launcher.stdout.log`:
```
[CONTEXT-ROT WARN] Turn input context (1511122 tokens) exceeded the threshold 50000. Model attention may degrade.
```
Ground truth from the server for the same turn (`~/llama-server.log`, `task.n_tokens`):
the real prompt was **55163 tokens** (then 56273 for the next call). The warning is
off by ~27×.

### Cause
In `launcher/stanok.py`, `turn_input_context = inp + c_read + c_create` accumulates
over **every API call in the turn** (cumulative). The same cumulative value is used
both for the cache-hit-rate metric and for the rot threshold. The threshold is a
*live window* question ("how big is the context right now?"), so a cumulative sum over
many calls is the wrong quantity — it grows monotonically with the number of tool
calls, not with the context size.

### Fix
- Keep the cumulative sums for reporting / cache-hit-rate (they are correct there).
- Compute the rot indicator from the **live window** — the usage of the *last* API
  call of the turn (`input_tokens + cache_read_input_tokens + cache_creation_input_tokens`
  of that call), or the max over calls — **not** the sum. Use a separate variable so the
  two metrics cannot be confused again.
- The log line must print the live window (one number, comparable to `n_ctx` /
  `CLAUDE_CODE_AUTO_COMPACT_WINDOW`), e.g. `context window ~55k / n_ctx 123k`.

### Threshold — re-evaluate, do not just carry over 50000
`STANOK_CONTEXT_ROT_TOKENS` defaults to `50000`. The real per-turn context in cc064 was
55163 and the server `n_ctx` is 123136, with auto-compact at 95%. A threshold that fires
on every healthy run is noise. After fixing the metric, tie the threshold to the
configured window (e.g. a fraction of `CLAUDE_CODE_AUTO_COMPACT_WINDOW`) or raise it to a
value a healthy run does not reach — and state the chosen number + rationale in the code
comment. (This is the "отдельным заходом" item the operator deferred; do not silently
keep 50000.)

### Acceptance
- With a fixed synthetic turn (several API calls, known sizes), the logged window equals
  the last call's size, not the sum.
- On a real run, the printed number is the same order of magnitude as the server's
  `task.n_tokens` for that turn.
- The warning does NOT fire on a healthy ~55k-token turn.

---

## Part B — read-guard rejects the repo root as a search root

### Correction first (the earlier assumption is wrong)
`hooks/read-guard.sh:26` **already** reads both keys:
```python
print(ti.get('file_path') or ti.get('path') or '')
```
So "read-guard only looks at `file_path`" is not the bug. Do **not** "fix" that.

### Actual residual bugs (both reproduced in cc064)
1. **Repo root is rejected.** `Glob {pattern:"*", path:"/home/hermes/darkcast/stanok"}`
   or `{pattern:"*.js", path:"."}` → `ABS == REPO_ROOT`, and
   `case "$ABS" in "$REPO_ROOT"/*)` does **not** match the bare root (the pattern
   requires a `/` after the root). It falls to `deny "outside repo: <repo>"` — a
   *misleading* message, since the path is the repo itself. (Had it passed that
   check, line 49's `src/|tests/|docs/|tickets/` allowlist would have denied it
   anyway as "protected path".)
2. **`Glob` without `path`.** `{pattern:"**/*"}` carries no `path`/`file_path` →
   line 32 denies with `"no path in input"`, even though the implicit search root
   is the repo (cwd). Also misleading.

Net in cc064: 7 read-guard denials, of which several were these Glob cases; the
model then spent turns re-orienting.

### Fix — distinguish search-root permission from content-read permission
The guard receives `tool_name` in the same JSON. Branch on it:

- **`Glob`** — search only; it returns file **names**, never contents. Allow any
  search root **inside** the repo, including the bare repo root (`ABS == REPO_ROOT`)
  and a missing/`.` path (treat as repo root). Still deny anything **outside** the
  repo.
- **`Read` | `Grep`** — content access. Keep the existing restriction to
  `src/ tests/ docs/ tickets/` unchanged. Denying `scripts/` and `hooks/` reads is
  **intentional** — do not widen this allowlist.
- Fix the root match: `ABS == REPO_ROOT || ABS starts with REPO_ROOT/`.
- Make the deny messages accurate (a repo-root Glob must not say "outside repo").

### Explicitly out of scope
- Do not add `scripts/` (or any other dir) to the Read/Grep allowlist.
- Do not change what `Read`/`Grep` may reach.

**Why `scripts/` stays unreadable:** `CLAUDE.md` already hands the model the exact
invocation contract (`bash scripts/run.sh test tests/<module>.test.js`), so reading
`run.sh`'s source is **not needed to use it correctly**. But `run.sh` *is* the gate
that decides pass/fail, so a Read of it is **reconnaissance value for an attempt to
bypass the gate**. There is no legitimate correctness motive that outweighs that, so
the exclusion holds — the decision and its reason are fixed together here so a future
pass does not "helpfully" widen it.

### Acceptance
- `Glob {pattern:"*.js", path:"."}`, `Glob {pattern:"*", path:"<repo>"}` and
  `Glob {pattern:"**/*"}` (no path) all pass through read-guard (allow).
- `Glob {path:"/etc"}` and `Read {file_path:"<repo>/hooks/read-guard.sh"}` are still denied.
- By construction the machine still cannot Read/Grep outside `src/tests/docs/tickets`.

---

## Invariants
- No change to verifier/bash-gate hook behaviour, `sandbox-run.sh`, or the sandbox settings.
- No new external dependencies.
- Keep the shell/Python style of the surrounding code; no drive-by refactors.

## Final report (≤ 5 lines)
1. TASK: DONE / PARTIAL (A / B)
2. Files: launcher/stanok.py, hooks/read-guard.sh
3. A: window metric = last call; threshold = <value> (rationale)
4. B: Glob root/`.`/no-path allowed; Read/Grep allowlist unchanged
5. Evidence: before/after numbers and a read-guard allow/deny matrix
