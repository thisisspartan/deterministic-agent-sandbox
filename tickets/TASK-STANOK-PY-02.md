# TASK-STANOK-PY-02 — Python stack: minimal JSON parser/renderer (no stdlib json)

impl: src/minjson.py
test: tests/minjson_test.py
docs: docs/minjson.md

Implement a small, dependency-free JSON module in Python 3. You may NOT use
the stdlib `json` module anywhere in `src/minjson.py` (hand-written parser and
renderer). Read every rule before writing code — the edge cases are the point.

## Contract

`src/minjson.py` exposes exactly two functions:

### `loads(text: str)` — parse ONE JSON document into Python values
- Objects -> `dict` (insertion order preserved), arrays -> `list`,
  strings -> `str`, numbers -> `int` or `float`, `true`/`false` -> `bool`,
  `null` -> `None`.
- Strings: double-quoted. Recognized escapes: `\"`, `\\`, `\/`, `\b`, `\f`,
  `\n`, `\r`, `\t`, and `\uXXXX` (exactly 4 hex digits, producing the
  corresponding Unicode character). ANY other escape sequence is malformed.
- Numbers: optional `-`, then digits; optional `.` + digits; optional
  `e`/`E` + optional sign + digits. A number with no `.` and no exponent is
  an `int`; otherwise a `float`. `-0` parses to `0` (int).
- Duplicate object keys: the LAST occurrence wins.
- Whitespace (space, `\t`, `\n`, `\r`) is allowed between tokens only.
- Malformed input raises `ValueError`: trailing garbage after the document,
  missing comma/colon, unclosed object/array, invalid escape, invalid `\u`
  hex digits, empty input, a number like `1.2.3` or `01`.

### `dumps(obj) -> str` — render a Python value to compact JSON text
- Compact separators: `,` between items, `:` between key and value, no
  spaces anywhere.
- `dict` keys in insertion order; keys must be `str`.
- `str`: escape `"` and `\`; control characters below U+0020 use the short
  forms `\b \f \n \r \t` where available, otherwise `\u00XX`. Non-ASCII
  characters are emitted as-is (NOT `\u`-escaped).
- `bool` -> `true`/`false`, `None` -> `null`, `int` -> decimal digits,
  `float` -> `repr()` form.
- Round-trip: for any supported `obj`, `loads(dumps(obj)) == obj`.

## Test file requirements (`tests/minjson_test.py`)
- A PLAIN Python script (no pytest, no unittest discovery): `run.sh` executes
  it as `python3 tests/minjson_test.py`; exit code 0 = all pass, non-zero = fail.
- Import the module by adding the repo root to `sys.path` first:
  `sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))`
  then `from src.minjson import loads, dumps`.
- The module must be import-safe: no side effects on import, no top-level
  `input()`/blocking calls (`run.sh smoke` imports it with stdin=/dev/null).
- Cover AT LEAST these cases (write them as explicit assertions):
  - `loads("{}") == {}` and `loads("[]") == []`
  - `loads('{"a": 1}') == {"a": 1}`
  - `loads('{"a": 1, "a": 2}') == {"a": 2}`          (duplicate key: last wins)
  - `loads('{"n": [1, 2.5, -3, 1e2, -0]}') == {"n": [1, 2.5, -3, 100.0, 0]}`
  - `isinstance(loads('{"n": 1}')["n"], int)` and
    `isinstance(loads('{"n": 1e2}')["n"], float)`
  - `loads('{"s": "A\\u0042\\n\\"q\\""}') == {"s": 'AB\n"q"'}`
  - `loads('{"t": true, "f": false, "n": null}') == {"t": True, "f": False, "n": None}`
  - `loads('  { "a" : [ 1 , 2 ] }  ') == {"a": [1, 2]}`   (whitespace)
  - `ValueError` for each of: `loads('{"a": 1}x')`, `loads('{"a": 1,}')`,
    `loads('{"a" 1}')`, `loads('{"a": "\\q"}')`, `loads('{"a": "\\u00G1"}')`,
    `loads('{"a": 1.2.3}')`, `loads('{"a": 01}')`, `loads("")`
  - `dumps({"a": 1}) == '{"a":1}'`
  - `dumps([1, "x", None, True]) == '[1,"x",null,true]'`
  - `dumps({"s": 'a"b\nc'}) == '{"s":"a\\"b\\nc"}'`
  - `dumps({"f": 1.5}) == '{"f":1.5}'`
  - round-trip: `obj = {"a": [1, 2.5, "x\ty", None], "b": {"c": True}}`;
    `loads(dumps(obj)) == obj`

## Deliverables
1. `tests/minjson_test.py` — write FIRST; the red phase (failing test) is
   expected and correct.
2. `src/minjson.py` — implementation (stdlib only, NO `json` import).
3. `docs/minjson.md` — one short paragraph describing the module contract.

## Verification
```
bash scripts/run.sh test tests/minjson_test.py
```

Final report (STRICTLY <= 5 lines):
1. TASK: DONE
2. Files: src/minjson.py, tests/minjson_test.py, docs/minjson.md
3. Tests: PASS
