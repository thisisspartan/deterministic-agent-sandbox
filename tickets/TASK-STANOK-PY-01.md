# TASK-STANOK-PY-01 — Python stack: minimal RFC 4180 CSV parser/renderer

impl: src/csvlite.py
test: tests/csvlite_test.py
docs: docs/csvlite.md

Implement a small, dependency-free CSV module in Python 3 (stdlib only).
This is a real multi-edge-case contract — read every rule before writing code.

## Contract

`src/csvlite.py` exposes exactly two functions:

### `parse(text: str) -> list[list[str]]`
Parse CSV text into a list of records (each a list of string fields).
Rules (all mandatory):
1. Fields are separated by `,`. Records are separated by `\n` or `\r\n`.
   A bare `\r` (NOT followed by `\n`) is an ordinary character inside a field,
   NOT a record separator.
2. A field may be quoted: it starts with `"` and ends with the next `"`.
   Inside a quoted field, `""` is an escaped literal `"`. Commas and
   newlines (`\n` and `\r\n`) inside a quoted field are literal content.
3. Unquoted fields run until the next `,` or record separator. No trimming:
   spaces are significant and preserved.
4. A trailing record separator at the end of the text does NOT produce an
   empty final record. `parse("")` returns `[]`.
5. An unterminated quoted field (opening `"` with no closing `"` before the
   record ends) is malformed: raise `ValueError`.

### `render(rows: list[list[str]]) -> str`
Render rows back to CSV text:
1. Fields joined by `,`, records joined by `\n`. NO trailing newline.
2. A field is quoted ONLY if it contains at least one of: `,`, `"`, `\n`,
   `\r`. Embedded `"` characters are doubled (`""`).
3. Round-trip: for any `rows`, `parse(render(rows)) == rows`.

## Test file requirements (`tests/csvlite_test.py`)
- A PLAIN Python script (no pytest, no unittest discovery): `run.sh` executes
  it as `python3 tests/csvlite_test.py`; exit code 0 = all pass, non-zero = fail.
- Import the module by adding the repo root to `sys.path` first:
  `sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))`
  then `from src.csvlite import parse, render`.
- The module must be import-safe: no side effects on import, no top-level
  `input()`/blocking calls (`run.sh smoke` imports it with stdin=/dev/null).
- Cover AT LEAST these cases (write them as explicit assertions):
  - `parse("") == []`
  - `parse("a,b\n") == [["a", "b"]]`            (trailing newline: no empty record)
  - `parse("a,b\nc,d") == [["a", "b"], ["c", "d"]]`
  - `parse("a,b\r\nc,d") == [["a", "b"], ["c", "d"]]`   (CRLF separator)
  - `parse("a\rb") == [["a\rb"]]`              (bare \r is literal)
  - `parse('"x,y",z') == [["x,y", "z"]]`        (comma inside quotes)
  - `parse('"a""b",c') == [["a\"b", "c"]]`      (escaped quote)
  - `parse('"line1\nline2",b') == [["line1\nline2", "b"]]`  (newline inside quotes)
  - `parse('""') == [[""]]`                     (empty quoted field)
  - `parse(" , ") == [[" ", " "]]`              (no trimming)
  - `parse('"unclosed')` raises `ValueError`
  - `render([["a", "b"]]) == "a,b"`
  - `render([["x,y", "z"]]) == '"x,y",z'`
  - `render([['a"b']]) == '"a""b"'`
  - `render([["l1\nl2"]]) == '"l1\nl2"'`
  - round-trip: `rows = [["a", "b,c"], ['d"e', "f\ng"], ["h\r", ""]]`;
    `parse(render(rows)) == rows`

## Deliverables
1. `tests/csvlite_test.py` — write FIRST; the red phase (failing test) is
   expected and correct.
2. `src/csvlite.py` — implementation (stdlib only).
3. `docs/csvlite.md` — one short paragraph describing the module contract.

## Verification
```
bash scripts/run.sh test tests/csvlite_test.py
```

Final report (STRICTLY <= 5 lines):
1. TASK: DONE
2. Files: src/csvlite.py, tests/csvlite_test.py, docs/csvlite.md
3. Tests: PASS
