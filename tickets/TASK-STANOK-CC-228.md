# TASK-STANOK-CC-228: k8s smoke — in-Pod Opik reachability under the DNS blackout (Package 1 closing gate, part 2)

impl: src/k8s_net_opik.py
test: tests/k8s_net_opik_test.py

run.sh: exists

## Context

ACCEPTANCE ticket for in-Pod Opik tracing under the NEW Package 1 NetworkPolicy
(full worker DNS egress blackout: no kube-dns rule; egress only to the literal-IP
/32 endpoints on port 8080). The worker Pod receives the Opik backend address
through the environment variable `STANOK_OPIK_TRACE_URL` (a full URL, e.g.
`http://192.168.122.156:8080/v1/private/otel`) — the tracing config is ENV-only,
no git-tree file changes. Your test proves from INSIDE the Pod that the backend
address from the env is actually reachable WITHOUT any name resolution — this is
what makes the run's traces register in Opik under the blackout.

## Requirement

`src/k8s_net_opik.py`:
- `mul(a, b)` -> `a * b`.
- `trace_endpoint_parts(url)` -> `(host, port)` parsed from an
  `http://host:port/path` URL with stdlib `urllib.parse`; `port` is an `int`.

`tests/k8s_net_opik_test.py` (pytest, `def test_*`):
1. `mul(2, 3) == 6`; zero identity `mul(0, x) == 0`; commutativity.
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

- `scripts/run.sh test tests/k8s_net_opik_test.py` -> rc=0; `scripts/run.sh test --all` -> rc=0.
- Create NO files other than the two declared ones.

## Expected pipeline outcome (host-side, checked by the supervisor — not by you)

Payload block accepted (nonce match) → `evidence/<label>/` contains summary.json +
changes.patch → contract clean → fresh Job green (test 3 SKIPPED there by design) →
final verdict PASS, rc=0, patch applied to the live tree; the host-issued
`opik_traces` field must be > 0 (the Pod's OTLP export reaches the backend by IP).
