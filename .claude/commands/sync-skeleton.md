---
description: Sync darkcast infrastructure into skeleton-pub and push to remote
---

Run the skeleton sync now, from the project root:

    ./sync-skeleton.sh

It mirrors darkcast **infrastructure** (the `stanok` submodule infra + top-level
scripts) into `~/skeleton-pub`, keeps machine-generated code (`stanok/src|tests|docs`)
and project history (tickets, review docs, evidence) OUT of the destination, commits
both repos, and pushes both to their GitHub remotes.

Report only the final `OK:` status line and any error. Do not read logs or poll.
