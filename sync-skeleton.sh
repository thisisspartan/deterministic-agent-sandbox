#!/usr/bin/env bash
#
# sync-skeleton.sh — mirror darkcast INFRASTRUCTURE into skeleton-pub and push.
#
# What it syncs:
#   * submodule stanok/  — all tracked infra files EXCEPT machine-generated code
#                          (src/, tests/, docs/ stay empty, only .gitkeep kept)
#   * top-level           — infra scripts (P0-launch.sh, e2e.sh, .gitmodules,
#                          .gitignore, CLAUDE.supervisor.md)
# What it keeps as clean templates (NOT overwritten):
#   * CONTEXT.md, README.md, specs/STATUS.md, tickets/.gitkeep
# What it never copies:
#   * machine code (stanok/src|tests|docs), project tickets, review/audit docs,
#     evidence/, .venv/, IDE dirs, dotfiles
#
# Usage:
#   ./sync-skeleton.sh            # sync + commit + push (default)
#   ./sync-skeleton.sh --no-push  # sync + commit only
#   SRC=... DST=... ./sync-skeleton.sh   # override the two repos
#
set -euo pipefail
shopt -s nullglob

SRC="${SRC:-/home/hermes/darkcast}"
DST="${DST:-/home/hermes/skeleton-pub}"
DST_STANOK="$DST/stanok"
PUSH=1
[[ "${1:-}" == "--no-push" ]] && PUSH=0

die() { echo "ERROR: $*" >&2; exit 1; }

# --- sanity (fail-closed) ---
[[ -d "$SRC/.git" ]]        || die "SRC is not a git repo: $SRC"
[[ -d "$DST/.git" ]]        || die "DST is not a git repo: $DST"
[[ -e "$DST_STANOK/.git" ]] || die "DST submodule not checked out: $DST_STANOK"
[[ -z "$(git -C "$DST" status --porcelain)" ]]        || die "DST top-level is dirty — commit/stash first"
[[ -z "$(git -C "$DST_STANOK" status --porcelain)" ]] || die "DST submodule is dirty — commit/stash first"

# --- [1/4] submodule: mirror infra, exclude machine code ---
echo "[1/4] submodule infra sync"
mapfile -t src_files < <(git -C "$SRC/stanok" ls-files)
sync_set=()
for f in "${src_files[@]}"; do
  case "$f" in
    src/*|tests/*|docs/*) [[ "$f" == *.gitkeep ]] && sync_set+=("$f") ;;
    *)                    sync_set+=("$f") ;;
  esac
done

cd "$DST_STANOK"
for f in "${sync_set[@]}"; do
  mkdir -p "$(dirname "$f")"
  cp "$SRC/stanok/$f" "$f"
done

# remove tracked files that are no longer in the sync set (obsolete infra / stray machine code)
mapfile -t dst_files < <(git ls-files)
for f in "${dst_files[@]}"; do
  if ! printf '%s\n' "${sync_set[@]}" | grep -qxF "$f"; then
    git rm -q -- "$f"
  fi
done

# keep the code dirs present but empty
for d in src tests docs; do
  mkdir -p "$d"
  [[ -f "$d/.gitkeep" ]] || touch "$d/.gitkeep"
done

# adapt machine-specific absolute paths in the sandbox settings (SRC -> DST)
if [[ -f .claude/settings.stanok.json ]]; then
  sed -i "s|$SRC/stanok|$DST_STANOK|g" .claude/settings.stanok.json
fi

# --- [2/4] top-level: mirror infra scripts, keep clean templates ---
echo "[2/4] top-level infra sync"
cd "$DST"
for f in P0-launch.sh .gitmodules .gitignore CLAUDE.supervisor.md e2e.sh; do
  if [[ -f "$SRC/$f" ]]; then
    cp "$SRC/$f" "$f"
    [[ "$f" == *.sh ]] && chmod +x "$f"
  fi
done
# keep the skeleton clean: drop any project tickets / review docs that wandered in
for f in tickets/TASK-*.md specs/AUDIT-*.md specs/REDTEAM-*.md specs/REVIEW-*.md; do
  [[ -e "$f" ]] && git rm -q -- "$f"
done

# --- [3/4] commit (only if changed) ---
echo "[3/4] commit"
cd "$DST_STANOK"
git add -A
if [[ -n "$(git status --porcelain)" ]]; then
  git commit -q --no-verify -m "sync infra from darkcast ($(date +%F))"
  echo "  submodule committed"
else
  echo "  submodule: no changes"
fi
cd "$DST"
git add -A
if [[ -n "$(git status --porcelain)" ]]; then
  git commit -q --no-verify -m "sync infra from darkcast ($(date +%F))"
  echo "  top-level committed"
else
  echo "  top-level: no changes"
fi

# --- [4/4] push (submodule first so the gitlink resolves) ---
if (( PUSH )); then
  echo "[4/4] push"
  git -C "$DST_STANOK" push origin main
  git -C "$DST" push origin main
else
  echo "[4/4] push skipped (--no-push)"
fi

echo "OK: skeleton-pub synced$( (( PUSH )) && echo " + pushed")"
