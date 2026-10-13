# TASK-STANOK-CC-260 (SMOKE, post-P5): image without bubblewrap — its pin test

test: tests/no_bwrap_image_test.py
docs: docs/no-bwrap-image.md

run.sh: exists

## Context

This is a SMOKE ticket: its purpose is to exercise the launch pipeline
end-to-end on the REBUILT machine image (P5: the `bubblewrap` apt package was
removed from the Dockerfile — the Pod runs unsandboxed natively: cli.js
defaults sandbox off, the settings carry no sandbox block). Project stack:
Python, pytest (`tests/**/*_test.py`), entrypoint `scripts/run.sh` exists —
use it as-is. stdlib only. Do not touch `src/`, `scripts/`, `launcher/`,
`k8s/`. No new dependencies.

## Requirement

`docs/no-bwrap-image.md` — at most 30 lines, plain markdown, describing the
image contract as it works today:

- the image carries NO bubblewrap/bwrap: the claude-code native sandbox is not
  enabled (the machine settings have no sandbox block; cli.js defaults
  sandbox.enabled to false), so the CLI needs no bwrap binary at all;
- the runtime boundary is the worker Job itself: non-root (UID 10001),
  all capabilities dropped, RuntimeDefault seccomp, read-only root
  filesystem, NetworkPolicy egress (only the model server and the Opik
  tracing backend reachable);
- `socat` stays in the image: the CLI hard-fails at startup without it;
- the image stays plain-docker-runnable: doctor's image preflight
  (`preflight_image`) probes it with `docker run --rm` plus the digest LABEL
  check.

Do not invent facts beyond the four points above.

## Tests (`tests/no_bwrap_image_test.py`, at least 4 test functions)

- the docs file exists, is valid UTF-8 and at most 30 lines (read it relative
  to the repo root — the test file's own location,
  `Path(__file__).resolve().parents[1] / "docs" / "no-bwrap-image.md"`);
- it mentions all four contract points (substring checks: `bwrap`,
  `NetworkPolicy`, `socat`, `preflight_image`);
- Pod-only invariant (guard it with
  `pytest.mark.skipif(os.environ.get("STANOK_IN_POD") != "1", ...)` — the
  CC-232 convention): `shutil.which("bwrap") is None` — the running image
  really carries no bubblewrap;
- Pod-only invariant (same guard): `shutil.which("socat") is not None` — the
  CLI's hard-fail startup dependency is present in the image.

TDD: write the tests first (red: the docs file does not exist), then write
the docs file to green. No other files.
