# TASK-STANOK-CC-124 — Kill-list 3.4: delete README "Архитектура v4.2" narrative

Supervisor-executed (docs only). Follows `specs/REVIEW-KISS-CLI-FIRST-2026-09-24.md` §3.4.

## Finding

`README.md` (and the identical `stanok/README.md`) §139-393 carried an "Architecture
(STANOK v4.2 / CC-106)" section: Control Plane / Data Plane / Inference Gateway /
POSIX ABI / Namespace Separation / an FSM state diagram. This is **vocabulary, not code** —
it renames ordinary components (the python supervisor, docker, `run.sh`, rc codes) in
grand-sounding terms and makes readers hunt for an architecture that does not exist.
It is the layer of language that produced the "запутались" feeling.

## Change

Replace the 255-line narrative with a short factual pointer block ("## Architecture
references") to the documents that actually describe the boundary, mount layout, the
`run.sh` contract, and the rc namespace:
`specs/HANDOFF-ARCH-REVIEW.md`, `specs/SPEC-SESSION-PLAN-2026-09-24.md`,
`specs/REVIEW-KISS-CLI-FIRST-2026-09-24.md`, `CLAUDE.supervisor.md`.
The factual "How it works" section (§49-138) and the rc table are **kept**.

Both copies edited in lockstep (they were verified byte-identical before the edit).
399 → 154 lines.

## Verification

Docs only — no code path. `doctor.sh` re-run to confirm green.
