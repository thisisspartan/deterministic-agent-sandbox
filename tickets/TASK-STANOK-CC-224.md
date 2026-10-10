# TASK-STANOK-CC-224: k8s smoke — NetworkPolicy isolation probe (LAN/Internet denied from the Pod)

test: tests/k8s_net_test.py

run.sh: exists

## Context

ACCEPTANCE ticket for the K8s runner's NetworkPolicy (SPEC-STANOK-K8S-RUNTIME-2026-10-10
§7/§9). You write a test that probes the Pod's network from the inside. The test asserts
ONLY the negative side of the policy, because it must be green in BOTH the worker Pod
(egress: model + kube-dns + Opik only) and the fresh-check Pod (deny-all network).
Reachability of the model itself is proven by the run working at all — do NOT probe the
model endpoint (192.168.8.131:8080) in the test: it would fail in the fresh Pod by design.

## Requirement

`tests/k8s_net_test.py` (pytest, `def test_*`) — probes, each with `socket` and a timeout
of at most 3 seconds, that the following addresses are UNREACHABLE from the Pod (any
OSError — timeout, refused, no route — counts as unreachable; a successful connect is a
failure of the test):

1. `192.168.8.131:22` — the model host's SSH port: the NetworkPolicy allows that IP only
   on the model port, so port 22 must be denied (port-level check).
2. `1.1.1.1:80` — Internet (a live listener: if egress were open, connect would succeed).
3. `8.8.8.8:53` — external DNS over TCP (cluster kube-dns is allowed; external DNS is not).

Use raw IPs only (no hostname resolution in the probes). No third-party packages —
stdlib `socket` only.

## Acceptance criteria

- `scripts/run.sh test tests/k8s_net_test.py` -> rc=0 when the NetworkPolicy is correct;
  `scripts/run.sh test --all` -> rc=0.
- Create NO files other than the declared test file.

## Expected pipeline outcome (host-side, checked by the supervisor — not by you)

Worker Pod: test green (policy correct) → fresh Pod (deny-all): test green → verdict PASS,
rc=0. If the policy leaks LAN/Internet egress, the worker-Pod test goes red — that is the
defect this ticket exists to catch.
