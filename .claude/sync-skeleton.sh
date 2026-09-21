#!/usr/bin/env bash
#
# sync-skeleton.sh — mirror THIS repo's INFRASTRUCTURE into skeleton-pub.
#
#   SRC = the repo you run it in (default: current git toplevel; override SRC=...)
#   DST = skeleton-pub (default: /home/hermes/skeleton-pub; override DST=...)
#
# Syncs infrastructure only. Machine-generated code (stanok/src|tests|docs) and
# project history (tickets, review/audit docs, evidence) are NEVER copied.
# Clean templates (CONTEXT.md, README.md, specs/STATUS.md, tickets/.gitkeep) are kept.
#
# Usage:
#   ./sync-skeleton.sh --diff          # preview: show what would change, no changes made
#   ./sync-skeleton.sh                 # apply: sync + commit + push
#   ./sync-skeleton.sh --no-push       # apply: sync + commit, no push
#
set -euo pipefail
shopt -s nullglob

SRC="${SRC:-$(git rev-parse --show-toplevel)}"
DST="${DST:-/home/hermes/skeleton-pub}"
DST_STANOK="$DST/stanok"
PUSH=1
MODE="apply"
for arg in "$@"; do
  case "$arg" in
    --no-push) PUSH=0 ;;
    --diff)    MODE="diff" ;;
  esac
done

die() { echo "ERROR: $*" >&2; exit 1; }

# --- sanity (fail-closed) ---
[[ -d "$SRC/.git" ]]        || die "SRC is not a git repo: $SRC"
[[ -d "$DST/.git" ]]        || die "DST is not a git repo: $DST"
[[ -e "$DST_STANOK/.git" ]] || die "DST submodule not checked out: $DST_STANOK"
[[ -d "$SRC/stanok" ]]      || die "SRC has no stanok/ : $SRC"

# --- build the submodule sync set (infra only, exclude machine code) ---
mapfile -t src_files < <(git -C "$SRC/stanok" ls-files)
sync_set=()
for f in "${src_files[@]}"; do
  case "$f" in
    src/*|tests/*|docs/*) [[ "$f" == *.gitkeep ]] && sync_set+=("$f") ;;
    *)                    sync_set+=("$f") ;;
  esac
done
mapfile -t dst_files < <(git -C "$DST_STANOK" ls-files)
declare -A dst_tracked=()
for f in "${dst_files[@]}"; do dst_tracked["$f"]=1; done

# --- classify submodule changes ---
sub_add=(); sub_mod=(); sub_rem=()
for f in "${sync_set[@]}"; do
  if [[ -z "${dst_tracked[$f]:-}" ]]; then
    sub_add+=("$f")
  elif [[ "$f" == ".claude/settings.stanok.json" ]]; then
    # compare with the sandbox paths already adapted to DST, so the diff shows the
    # true net change (the apply step rewrites these paths via sed)
    if ! diff -q <(sed "s|$SRC/stanok|$DST_STANOK|g" "$SRC/stanok/$f") "$DST_STANOK/$f" >/dev/null 2>&1; then
      sub_mod+=("$f")
    fi
  elif ! diff -q "$SRC/stanok/$f" "$DST_STANOK/$f" >/dev/null 2>&1; then
    sub_mod+=("$f")
  fi
done
for f in "${dst_files[@]}"; do
  if ! printf '%s\n' "${sync_set[@]}" | grep -qxF "$f"; then
    sub_rem+=("$f")
  fi
done

# --- classify top-level changes ---
top_sync=(P0-launch.sh .gitmodules .gitignore CLAUDE.supervisor.md .claude/e2e.sh)
top_add=(); top_mod=()
for f in "${top_sync[@]}"; do
  [[ -f "$SRC/$f" ]] || continue
  if [[ ! -f "$DST/$f" ]] || ! git -C "$DST" ls-files --error-unmatch "$f" >/dev/null 2>&1; then
    top_add+=("$f")
  elif ! diff -q "$SRC/$f" "$DST/$f" >/dev/null 2>&1; then
    top_mod+=("$f")
  fi
done

# --- diff mode: print the plan and exit (no changes) ---
if [[ "$MODE" == "diff" ]]; then
  echo "SRC: $SRC"
  echo "DST: $DST"
  echo ""
  echo "=== submodule (stanok/) ==="
  echo "ADD (${#sub_add[@]}):"
  if (( ${#sub_add[@]} )); then printf '  %s\n' "${sub_add[@]}"; fi
  echo "MODIFY (${#sub_mod[@]}):"
  if (( ${#sub_mod[@]} )); then printf '  %s\n' "${sub_mod[@]}"; fi
  echo "REMOVE (${#sub_rem[@]}):"
  if (( ${#sub_rem[@]} )); then printf '  %s\n' "${sub_rem[@]}"; fi
  echo ""
  echo "=== top-level ==="
  echo "ADD (${#top_add[@]}):"
  if (( ${#top_add[@]} )); then printf '  %s\n' "${top_add[@]}"; fi
  echo "MODIFY (${#top_mod[@]}):"
  if (( ${#top_mod[@]} )); then printf '  %s\n' "${top_mod[@]}"; fi
  echo ""
  total=$(( ${#sub_add[@]} + ${#sub_mod[@]} + ${#sub_rem[@]} + ${#top_add[@]} + ${#top_mod[@]} ))
  echo "TOTAL changes: $total"
  exit 0
fi

# --- apply mode: fail-closed on dirty DST ---
[[ -z "$(git -C "$DST" status --porcelain)" ]]        || die "DST top-level is dirty — commit/stash first"
[[ -z "$(git -C "$DST_STANOK" status --porcelain)" ]] || die "DST submodule is dirty — commit/stash first"

# --- [1/4] submodule: mirror infra, exclude machine code ---
echo "[1/4] submodule infra sync"
cd "$DST_STANOK"
for f in "${sync_set[@]}"; do
  mkdir -p "$(dirname "$f")"
  cp "$SRC/stanok/$f" "$f"
done
for f in "${dst_files[@]}"; do
  if ! printf '%s\n' "${sync_set[@]}" | grep -qxF "$f"; then
    git rm -q -- "$f"
  fi
done
for d in src tests docs; do
  mkdir -p "$d"; [[ -f "$d/.gitkeep" ]] || touch "$d/.gitkeep"
done
if [[ -f .claude/settings.stanok.json ]]; then
  sed -i "s|$SRC/stanok|$DST_STANOK|g" .claude/settings.stanok.json
fi

# --- [2/4] top-level: mirror infra scripts, keep clean templates ---
echo "[2/4] top-level infra sync"
cd "$DST"
for f in "${top_sync[@]}"; do
  if [[ -f "$SRC/$f" ]]; then
    mkdir -p "$(dirname "$f")"
    cp "$SRC/$f" "$f"
    [[ "$f" == *.sh ]] && chmod +x "$f"
  fi
done
for f in tickets/TASK-*.md specs/AUDIT-*.md specs/REDTEAM-*.md specs/REVIEW-*.md; do
  [[ -e "$f" ]] && git rm -q -- "$f"
done

# --- [3/4] commit (only if changed) ---
echo "[3/4] commit"
cd "$DST_STANOK"
git add -A
if [[ -n "$(git status --porcelain)" ]]; then
  git commit -q --no-verify -m "sync infra from $(basename "$SRC") ($(date +%F))"
  echo "  submodule committed"
else
  echo "  submodule: no changes"
fi
cd "$DST"
git add -A
if [[ -n "$(git status --porcelain)" ]]; then
  git commit -q --no-verify -m "sync infra from $(basename "$SRC") ($(date +%F))"
  echo "  top-level committed"
else
  echo "  top-level: no changes"
fi

# --- [4/4] push (submodule first so the gitlink resolves) ---
if (( PUSH )); then
  echo "[4/4] push"
  git -C "$DST_STANOK" push origin main
  git -C "$DST" push origin main
  echo "OK: skeleton-pub synced + pushed"
else
  echo "[4/4] push skipped (--no-push)"
  echo "OK: skeleton-pub synced (local only)"
fi
