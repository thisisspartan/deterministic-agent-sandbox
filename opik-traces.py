#!/usr/bin/env python3
"""One-off Opik trace diagnosis (CC-159).

The self-hosted Opik traces API silently ignores all query filters
(`search`, `thread_id`, `startTime`, `endTime` all return the unfiltered
total), so this helper paginates the full trace list and filters
`metadata.thread_id` client-side.

Usage:
    python3 opik-traces.py <session_id> [<session_id> ...]
                          [--project PROJECT_ID] [--base URL]

Per session prints: trace count, min/max start_time, and the final
trace's model_output (truncated) + success flag. Exits non-zero if any
session has zero traces.

Stdlib only. One-off use AFTER a run has completed — never while the
machine is running (see CLAUDE.supervisor.md §6).
"""
import argparse
import json
import sys
import urllib.request

DEFAULT_PROJECT = "01a09a5b-4791-72c3-8a01-15ceebf0b48a"
DEFAULT_BASE = "http://localhost:5173"
PAGE_SIZE = 100


def fetch_all_traces(base: str, project: str) -> list:
    traces = []
    page = 1
    while True:
        url = (f"{base}/api/v1/private/traces"
               f"?project_id={project}&size={PAGE_SIZE}&page={page}")
        with urllib.request.urlopen(url, timeout=30) as r:
            data = json.load(r)
        items = data.get("content", [])
        if not items:
            break
        traces.extend(items)
        total = data.get("total", 0)
        if page * PAGE_SIZE >= total:
            break
        page += 1
    return traces


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("sessions", nargs="+", metavar="SESSION_ID",
                    help="Opik thread/session ID(s) to diagnose")
    ap.add_argument("--project", default=DEFAULT_PROJECT)
    ap.add_argument("--base", default=DEFAULT_BASE)
    args = ap.parse_args()

    want = set(args.sessions)
    traces = fetch_all_traces(args.base, args.project)

    by_session: dict[str, list] = {sid: [] for sid in want}
    for t in traces:
        tid = (t.get("metadata") or {}).get("thread_id")
        if tid in by_session:
            by_session[tid].append(t)

    rc = 0
    for sid in args.sessions:  # preserve argument order
        ts = by_session[sid]
        if not ts:
            print(f"{sid}: NO TRACES (exit non-zero)")
            rc = 1
            continue
        ts.sort(key=lambda t: t.get("start_time", ""))
        final = ts[-1]
        out = ((final.get("output") or {}).get("response") or {})
        model_output = " ".join((out.get("model_output") or "").split())
        if len(model_output) > 200:
            model_output = model_output[:200] + "…"
        success = (final.get("metadata") or {}).get("success")
        print(f"{sid}: {len(ts)} traces, "
              f"{ts[0].get('start_time')} .. {final.get('start_time')}, "
              f"final success={success}")
        if model_output:
            print(f"  final report: {model_output}")
    return rc


if __name__ == "__main__":
    sys.exit(main())
