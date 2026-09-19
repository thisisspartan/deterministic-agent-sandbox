# TASK-STANOK-PY-03 — Python stack: unified diff generator (LCS-based, exact format)

impl: src/udiff.py
test: tests/udiff_test.py
docs: docs/udiff.md

Implement a small, dependency-free unified diff generator in Python 3
(stdlib only). The EXACT output string is the contract — whitespace and
line numbers matter. Read every rule before writing code.

## Contract

`src/udiff.py` exposes exactly one function:

### `diff(old: list[str], new: list[str], context: int = 3) -> str`
Compute the unified diff of two line lists (lines are compared exactly,
no trailing-newline semantics — the inputs are already split lines).

Algorithm:
1. Align the two lists by their LONGEST COMMON SUBSEQUENCE (LCS) of lines.
   Lines in the LCS are unchanged (context); old lines not in the LCS are
   deletions; new lines not in the LCS are insertions. (All test inputs
   below have a unique LCS alignment.)
2. Within one change block (a maximal run between two consecutive LCS
   matches that contains at least one deletion or insertion), ALL
   deletions are emitted BEFORE all insertions.

Hunk grouping:
3. A change block is expanded by `context` unchanged lines on each side
   (clamped at file boundaries).
4. Two change blocks MERGE into one hunk when the number of unchanged
   lines between them is <= 2 * context.
5. If there are no changes at all, return `""` (empty string).

Output format (exact):
6. Each hunk starts with a header line:
   `@@ -<os>,<oc> +<ns>,<nc> @@`
   - `os` = 1-based index of the first old line in the hunk (context
     included); if the hunk contains NO old lines at all (pure insertion
     with zero old context), `os` = the 1-based index of the old line
     immediately before the insertion point, or `0` if the insertion is
     at the very start.
   - `oc` = number of old lines in the hunk (context + deletions).
   - `ns`, `nc` — the same for the new file (for a hunk with no new
     lines: `ns` = the 1-based index of the new line immediately before
     the deletion point, or `0` if at the very start).
   - The counts are ALWAYS printed, even when 0 or 1.
7. Body lines, in order: unchanged -> ` ` + line (one leading space),
   deletion -> `-` + line, insertion -> `+` + line.
8. Every line of the output (headers and body) ends with `\n`, including
   the last. Hunks are emitted in file order with no blank line between
   them.

## Test file requirements (`tests/udiff_test.py`)
- A PLAIN Python script (no pytest, no unittest discovery): `run.sh` executes
  it as `python3 tests/udiff_test.py`; exit code 0 = all pass, non-zero = fail.
- Import the module by adding the repo root to `sys.path` first:
  `sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))`
  then `from src.udiff import diff`.
- The module must be import-safe: no side effects on import, no top-level
  `input()`/blocking calls (`run.sh smoke` imports it with stdin=/dev/null).
- Cover AT LEAST these cases (write them as explicit assertions on the
  EXACT output string):
  - `diff(["a", "b", "c"], ["a", "b", "c"]) == ""`
  - `diff(["a"], ["a"]) == ""`
  - `diff(["a", "b", "c"], ["a", "X", "c"]) == "@@ -1,3 +1,3 @@\n a\n-b\n+X\n c\n"`
  - `diff(["a", "b", "c"], ["a", "c"]) == "@@ -1,3 +1,2 @@\n a\n-b\n c\n"`
  - `diff(["b", "c"], ["a", "b", "c"]) == "@@ -1,2 +1,3 @@\n+a\n b\n c\n"`
  - `diff(["a", "b"], ["a", "X", "b"]) == "@@ -1,2 +1,3 @@\n a\n+X\n b\n"`
  - `diff(["a", "b", "c"], ["a", "X", "Y"]) == "@@ -1,3 +1,3 @@\n a\n-b\n-c\n+X\n+Y\n"`
  - merged hunk (context=3):
    `diff(["a", "b", "c", "d", "e"], ["a", "X", "c", "d", "Y"]) ==
    "@@ -1,5 +1,5 @@\n a\n-b\n+X\n c\n d\n-e\n+Y\n"`
  - two separate hunks (context=2):
    `diff(["a","b","c","d","e","f","g","h","i","j"],
          ["a","X","c","d","e","f","g","h","Y","j"], context=2) ==
    "@@ -1,4 +1,4 @@\n a\n-b\n+X\n c\n d\n@@ -7,4 +7,4 @@\n g\n h\n-i\n+Y\n j\n"`
  - empty old: `diff([], ["a", "b"]) == "@@ -0,0 +1,2 @@\n+a\n+b\n"`
  - empty new: `diff(["a", "b"], []) == "@@ -1,2 +0,0 @@\n-a\n-b\n"`

## Deliverables
1. `tests/udiff_test.py` — write FIRST; the red phase (failing test) is
   expected and correct.
2. `src/udiff.py` — implementation (stdlib only).
3. `docs/udiff.md` — one short paragraph describing the module contract.

## Verification
```
bash scripts/run.sh test tests/udiff_test.py
```

Final report (STRICTLY <= 5 lines):
1. TASK: DONE
2. Files: src/udiff.py, tests/udiff_test.py, docs/udiff.md
3. Tests: PASS
