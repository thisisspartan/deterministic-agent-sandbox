#!/usr/bin/env bash
# E2E pipeline test: launch the machine on a ticket, block until the run
# finishes, then verify evidence/<label>/summary.json (rc=0 + verifier=PASS).
#
# Usage: ./e2e.sh <ticket.md> <label>
# Exit: 0 = E2E-OK, 1 = E2E-FAIL (dirty tree / no summary / rc!=0 / verifier!=PASS)
set -u
set -o pipefail

TICKET="${1:?usage: ./e2e.sh <ticket.md> <label>}"
LABEL="${2:?usage: ./e2e.sh <ticket.md> <label>}"
ROOT="$(cd "$(dirname "$0")" && pwd)"
cd "$ROOT"

# Gate 1: clean submodule tree (mirrors launch.sh dirty-tree gate, rc=22).
if [[ -n "$(git -C stanok status --porcelain)" ]]; then
    echo "E2E-FAIL: dirty submodule tree — commit before launch" >&2
    exit 1
fi

# Gate 2: launch + blocking wait (single combined command, no polling).
./stanok/launch.sh run "$TICKET" "$LABEL" --background \
    && while ./stanok/launch.sh status "$LABEL" | grep -q '"state": "running"'; do sleep 15; done \
    && ./stanok/launch.sh status "$LABEL"

# Gate 3: verdict from summary.json.
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
