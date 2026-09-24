# TASK-STANOK-SMOKE-02 — Toolchain validation

test: tests/smoke_tools_test.py

## Goal
Validate that all curated tools are available and functioning inside the sandbox.

## Requirements
1. Use `Glob` or `Grep` to find the word "deterministic" inside `src/fire.py`.
2. Use `Bash` to create a file `$TMPDIR/proof.txt` containing the exact line you found.
3. Use `Write` to create `tests/smoke_tools_test.py` with a simple pytest that asserts `1 == 1`.
4. Do NOT modify `src/fire.py`.

Final report (STRICTLY <= 5 lines):
1. TASK: DONE
2. Files: tests/smoke_tools_test.py
3. Tests: PASS
