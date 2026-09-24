# TASK-STANOK-CC-132 — One source for zones/kinds (align the 3 literals + consumers)

Supervisor-executed (`launcher/` is RO in the container). Follows
`specs/AUDIT-STANOK-2026-09-24.md` §4 item 1 (evidence §1#2, §1#3; §1#7 is the
follow-up, see Non-goals).

## Finding

The zone list is written out 3 times, and the kind list disagrees with the
docstring that advertises it:

| site | literal | note |
|---|---|---|
| `sandbox.py:19` | `("src","tests","docs","scripts","evidence")` | `DEFAULT_RW_ZONES` — the rw mounts |
| `stanok.py:75` | `("src","tests","docs","scripts")` | `_DECLARED_ZONES` — path validation |
| `stanok.py:207` | `("src","tests","docs","scripts")` | `hidden_files_gate` |
| `stanok.py:516` | `("src","tests","docs","scripts")` | `prepare_workspace` |
| `stanok.py:96` | `impl:/test:/docs:/scripts:` | SessionPlan docstring — advertises a 5th kind that `_FILE_LINE_RE` (73) does not know |

Two of these are not a duplication: `_tests_manifest` (700/712) snapshots
`tests/**` + `scripts/run.sh` — the *protected* set, a different rule (and
widening it to all zones would snapshot `src/`+`docs/`, a behavior change). Left
alone; this row of the audit §1#3 was overstated (4 real dup sites, not 5).

## Change

- `sandbox.py`: `WRITABLE_ZONES = ("src","tests","docs","scripts")` is the ONE
  literal; `DEFAULT_RW_ZONES = WRITABLE_ZONES + ("evidence",)` (behavior
  unchanged — `evidence/` stays rw until CC-134).
- `stanok.py`: delete `_DECLARED_ZONES`; `_validate_declared_path`,
  `hidden_files_gate`, `prepare_workspace` and the rc=13 error message read
  `sandbox.WRITABLE_ZONES`.
- `stanok.py`: drop the ghost `scripts:` kind from the SessionPlan docstring —
  kinds are exactly `impl|test|docs|edit` (`_FILE_LINE_RE` is the source, and
  README:109 already said so). `scripts` is a ZONE; a path under `scripts/` is
  declared with an existing kind (`edit: scripts/run.sh`).

No behavior change for any valid ticket: the declared-zone set is the same
4-tuple, and the same paths are accepted/rejected.

## Verification

`py_compile`; 4 new hermetic tests in `test_session_plan.py` (`test_zones_have_one_source`,
`test_zone_consumers_read_the_constant` — patches `WRITABLE_ZONES` and watches
both consumers follow, `test_header_kinds_are_impl_test_docs_edit`,
`test_scripts_is_a_zone_not_a_kind`); `hooks/doctor.sh` — **119 passed, 2 skipped**
(was 115/2; +4).

## Non-goals

- **§1#7** (let a ticket declare root files / other top-level dirs: `go.mod`,
  `Cargo.toml`, `internal/`) — **deferred to CC-135 (T4)**, deliberately. The
  gate and the mounts must move in the SAME change: a widened allow-list without
  a matching rw mount would accept a ticket the container cannot execute. CC-132
  only makes the list a single constant so that derivation has one place to land.
- §1#2's alternative reading (add `scripts` to the regex) — rejected: kinds ≠
  zones, and `scripts:` would be a 4th synonym for `impl:`.
- §1#4 (`evidence/` exposure, CC-134), §1#1 (node_modules noise, CC-137).
