#!/usr/bin/env bash
# E2E pipeline test: launch the machine on a ticket, block until the run
# finishes, then verify evidence/<label>/summary.json (rc=0 + verifier=PASS).
#
# Usage: ./.claude/e2e.sh <ticket.md> <label>
# Exit: 0 = E2E-OK, 1 = E2E-FAIL (no summary / rc!=0 / verifier!=PASS)
# The dirty-tree gate is launch.sh's (rc=22) — single source, no copy here.
set -u
set -o pipefail

TICKET="${1:?usage: ./.claude/e2e.sh <ticket.md> <label>}"
LABEL="${2:?usage: ./.claude/e2e.sh <ticket.md> <label>}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

# Gate 1: launch + blocking wait. `--follow` is the sole background flag
# (CC-140/BL-1): it detaches the run and blocks in cmd_wait until the run is
# terminal, returning 0 for ANY terminal state (done/dead/missing — including
# a completed-but-failed run), 17 on a launch failure, 124 on the 45-min cap.
# The chain result is checked explicitly (no set -e): a launch failure must
# not fall through to Gate 2 with a misleading "no summary.json". A
# completed-but-failed run returns 0 here and is judged in Gate 2.
if ! ./stanok/launch.sh run "$TICKET" "$LABEL" --follow; then
    echo "E2E-FAIL: gate 1 (launch + wait) failed" >&2
    exit 1
fi

# Gate 2: verdict from summary.json.
SUMMARY="stanok/evidence/$LABEL/summary.json"
if [[ ! -f "$SUMMARY" ]]; then
    echo "E2E-FAIL: no summary.json at $SUMMARY" >&2
    exit 1
fi
python3 - "$SUMMARY" <<'PYEOF'
import json, sys
d = json.load(open(sys.argv[1], encoding="utf-8"))
rc, ver = d.get("rc"), d.get("verifier")
ok = rc == 0 and ver == "PASS"
print(f"E2E-{'OK' if ok else 'FAIL'}: rc={rc} verifier={ver} probe={d.get('probe_result')}")
if not ok:
    for k in ("errors", "failures"):
        if d.get(k):
            print(f"  {k}: {d[k]}", file=sys.stderr)
sys.exit(0 if ok else 1)
PYEOF
