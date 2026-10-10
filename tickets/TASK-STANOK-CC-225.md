# TASK-STANOK-CC-225: k8s smoke — in-Pod Opik tracing via ENV (backend reachable from the Pod)

impl: src/k8s_opik.py
test: tests/k8s_opik_test.py

run.sh: exists

## Context

ACCEPTANCE ticket for in-Pod Opik tracing (operator decision 2026-10-10). The
worker Pod now receives the Opik backend address through the environment
variable `STANOK_OPIK_TRACE_URL` (a full URL, e.g.
`http://192.168.122.156:8080/v1/private/otel`) — the tracing config is ENV-only,
no git-tree file changes. The NetworkPolicy allows the Pod egress to that host
and port. Your test proves from INSIDE the Pod that the backend address from the
env is actually reachable — this is what makes the run's traces register in Opik.

## Requirement

`src/k8s_opik.py`:
- `add(a, b)` -> `a + b`.
- `trace_endpoint_parts(url)` -> `(host, port)` parsed from an
  `http://host:port/path` URL with stdlib `urllib.parse`; `port` is an `int`.

`tests/k8s_opik_test.py` (pytest, `def test_*`):
1. `add(2, 3) == 5`.
2. `trace_endpoint_parts("http://192.168.122.156:8080/v1/private/otel")`
   returns `("192.168.122.156", 8080)`.
3. `test_opik_backend_reachable`: read `os.environ.get("STANOK_OPIK_TRACE_URL", "")`.
   If it is empty -> `pytest.skip("no Opik env in this Pod")` (the independent
   fresh-check Pod has no network by design — the test must be green there too).
   Otherwise: parse host/port with `trace_endpoint_parts`, then
   `socket.create_connection((host, port), timeout=5)` must SUCCEED — any
   `OSError` (timeout, refused, no route) is a test failure. No hostname
   resolution, no third-party packages — stdlib only.

## Acceptance criteria

- `scripts/run.sh test tests/k8s_opik_test.py` -> rc=0; `scripts/run.sh test --all` -> rc=0.
- Create NO files other than the two declared ones.

## Expected pipeline outcome (host-side, checked by the supervisor — not by you)

Worker Pod: all three tests green (env present, backend reachable) -> fresh Pod:
tests 1-2 green, test 3 skipped (no env, deny-all by design) -> verdict PASS, rc=0.
The host separately counts this session's traces in Opik and stamps them into the
report — zero traces means the OTLP export never arrived, which this ticket
exists to catch.
