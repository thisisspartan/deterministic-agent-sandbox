# TASK-STANOK-CC-145 — branch-line consolidation + history-rewrite decision

Supervisor-executed in the **CLI repo** (`~/git/claude-code-2.1.88`).
**Decision ticket — no code lands until the operator rules.**
Part of `specs/PLAN-cli-js-hygiene-2026-09-25.md` (F7, F8).

## Context

Six lines diverge from `origin/main` (`c8cd253`); none are merged into the
shipped `base`:

| ref | blob cli.js | commits beyond origin/main | carries |
|---|---|---|---|
| `stock` | `5e870b9b` | 17 | remote compaction (Gemini/Mistral) — **not in base** |
| `base` | `809caeef` | **31** | **shipped** |
| `main` | `29fbe302` | 8 | B1 think_low/think_medium — **not in base** |
| `dev` | `8dd4f5cc` | 8 | (checked out in another worktree) |
| `feature/git-command-protection` | `6ddd5776` | 3 | |

Consequence: a new edit applied to the wrong line silently never ships (the
bundle is whichever tree `setup.sh` copies — `base`). This is drift-by-topology.

## Decisions required (operator)

1. **Canonical line.** Declare `base` canonical; archive/delete the others? If
   any line holds work not in `base`, merge it first.
2. **Deliberate exclusions.** Is the shipped bundle intentionally without
   remote compaction (`stock`) and without B1 think_medium (`main`)? Yes/no —
   because both are live behavioral differences, not cosmetics.
3. **History rewrite?** Purge the 26 MB of `cli.js.bak-*` blobs from history and
   collapse the net-zero `ddf150b`+`0285301` add/revert pair, or leave history as
   is? Rewriting is destructive (every downstream sha changes, remotes need a
   force-push) — hence a separate decision from CC-142.
4. **`STANOK_TEMP` default.** Keep bundle default `1`, or follow the server
   default `0.2`? (Implementation lives in CC-144.)

## Change (only after the ruling)

- Record the decision in `CONTEXT.md` + this plan (§5) and tag/branch accordingly.
- If rewrite is approved: `git filter-repo` on a **clone**, verified backup first,
  then a coordinated force-push — never in place on the working repo.

## Verification

- Divergence re-check: `git rev-list --left-right --count base...<ref>` matches
  the ruling for every ref.
- `base:cli.js` blob still `809caeef…` unless a merge is explicitly approved.
- If rewritten: old and new `setup.sh` pin agree on the shipped file.

## Non-goals

- No bundle edits (that is CC-144).
- No deletion of a remote branch without an explicit per-branch instruction.
