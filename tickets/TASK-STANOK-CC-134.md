# TASK-STANOK-CC-134 — evidence/ is host-only (the container loses its rw view)

Supervisor-executed (`launcher/` is RO in the container). Follows
`specs/AUDIT-STANOK-2026-09-24.md` §1#4 (§4 item 3).

## Finding

`evidence/` was a writable mount: `DEFAULT_RW_ZONES = WRITABLE_ZONES +
("evidence",)` (sandbox.py) put `evidence/<label>` rw inside the container, and
`label_paths()` resolved to the same path on both sides (stanok.py:152). The
agent therefore had rw over the launcher's own verdict dir — `.running`,
`launcher.stdout.log`, `summary.json` — with only the cli.js deny
(`Read(evidence/**)`) standing between it and the file the supervisor reads.
§1#4: "keep evidence on the host only".

Correction to the audit's verification column: the e2e "`ls evidence/` inside
the container fails" is **wrong**. Docker layers mounts by specificity, so
dropping the `evidence:rw` carve-out reverts that path to the parent
`repo:ro` mount — the directory stays *visible*, the *write* is refused
(EROFS). The honest assertion is pinned below; a missing-path e2e would have
been a false test.

## Change

- `sandbox.py`: `DEFAULT_RW_ZONES` **deleted** — `WRITABLE_ZONES` is now both
  the one zone list and the one zone name;
  `sandbox_argv(rw_zones=WRITABLE_ZONES)`. No `evidence` rw mount is emitted.
- `stanok.py` `label_paths`: container-aware —
  `STANOK_IN_CONTAINER=1` → *both* dirs resolve to `LOG_DIR/<label>` (the rw
  mount the container already had). Routed in this one function, so every
  in-container writer follows automatically: `summary.json`,
  `launcher.stdout.log`, the `.running` marker.
- `stanok.py` `_publish_evidence(label)`: copies `summary.json` +
  `launcher.stdout.log` from `LOG_DIR/<label>` into `evidence/<label>` — the
  files that exist; no directory is created when nothing was staged (an
  aborted launch publishes nothing rather than a fake verdict).
- `run_sandboxed` finally: `docker_stop` → `_publish_evidence` → remove the
  marker. The order is load-bearing: the supervisor's wait loop keys on
  `.running`, so the summary must already sit in `evidence/` by the time
  `status` stops saying "running".
- `README.md`: the writable-zone list, the verdict paragraph, and the config
  table — the phantom `STANOK_EVIDENCE` row (no such variable in the code;
  the real one is `STANOK_LOG_DIR`) is replaced by the real row.

Host-side `label_paths` is unchanged, so the verdict contract the supervisor
reads (`evidence/<label>/summary.json`, `status`/`stop` on the host marker)
is identical. `evidence/` stays visible-but-`:ro` in the container.

## Verification

- `py_compile`.
- New `launcher/tests_harness/test_evidence_boundary.py`, 6 tests: the zone
  list has no `evidence`; `sandbox_argv` emits no `evidence…:rw` while keeping
  the repo `:ro` and the 4 zone carve-outs; container-aware `label_paths`;
  `_publish_evidence` copies the verdict and *only* the verdict (the session
  jsonl stays in LOG_DIR); absent staging → no-op; and a **real `docker run`**
  through the argv the launcher builds:
  `touch <repo>/src/probe` → `SRC-OK`, `touch <repo>/evidence/probe` →
  `EVIDENCE-DENIED`.
- The docker half reproduced by hand (same argv, image `stanok-machine:latest`):

```
$ docker run --rm -v /tmp/cc134probe:/tmp/cc134probe:ro \
    -v /tmp/cc134probe/repo/evidence:/tmp/cc134probe/repo/evidence:ro \
    --user uid:gid stanok-machine:latest \
    bash -c 'ls /tmp/cc134probe/repo/evidence; touch /tmp/cc134probe/repo/evidence/p; echo rc=$?'
touch: cannot touch '/tmp/cc134probe/repo/evidence/p': Read-only file system
rc=1
```

  `ls` succeeds (no "No such file"): the path is visible, the write is EROFS.
- `hooks/doctor.sh` — full suite **131 passed, 0 skipped on a clean tree**
  (+6; CC-133 = 125). Observed as 129 passed/2 skipped while this ticket was
  uncommitted: the pre-existing dirty-tree-dependent mock launches, skipped by
  design whenever the worktree is dirty.

## Non-goals

- **T4 (CC-135)** — per-file rw mounts derived from `plan.mutable_paths`.
  `tests/` + `scripts/` keep their zone-level rw mounts here; `WRITABLE_ZONES`
  is now the single place that derivation will land.
- The container keeps rw on `LOG_DIR` by necessity: it writes the session
  jsonl and the `pre-existing/` quarantine there. What left the container's rw
  view is `evidence/` (the verdict), not the log dir.
- Deeper hardening of the staging dir is a separate ticket. Residual, stated
  honestly: the container-side verdict is staged in an agent-writable
  directory. It cannot be **forged** into the published verdict — the
  container-side gates and `_rotate_stale_summary` run *before* the session,
  and `cmd_run`'s final `write_summary` (`open(..., "w")`) runs *after* it, so
  an agent-planted file is always overwritten. The worst the agent can do is
  make the final write fail → no published summary → fail-closed (the
  supervisor treats a missing summary as a failure, never as a PASS).
- §1#1 (`node_modules` noise filter, CC-137); T5 `_pretooluse_lock_hook`
  deletion (CC-136) stays gated on CC-135's e2e proof.
