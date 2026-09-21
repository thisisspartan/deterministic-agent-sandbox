# TASK-STANOK-JS-01 — JS stack: minimal RGB color utility

impl: src/rgb.js
test: tests/rgb.test.js
docs: docs/rgb.md

Implement a small, dependency-free RGB color module in Node.js (CommonJS,
node:test). This is a real multi-edge-case contract — read every rule before
writing code.

## Contract

`src/rgb.js` exports exactly three functions (CommonJS `module.exports`):

### `hexToRgb(hex) -> {r, g, b}`
Convert a hex color string to an object with integer channels 0-255.
Rules (all mandatory):
1. Input must be a string of exactly 7 characters: `#` followed by 6
   hexadecimal digits (`0-9a-fA-F`), e.g. `'#ff8000'`. Case-insensitive.
2. Returns `{r, g, b}` where each value is an integer 0-255
   (`'#ff8000'` -> `{r: 255, g: 128, b: 0}`).
3. Anything else (non-string, wrong length, missing `#`, non-hex character)
   throws `Error`.

### `rgbToHex({r, g, b}) -> string`
Convert an RGB object to a lowercase hex string.
Rules (all mandatory):
1. Input must be an object whose `r`, `g`, `b` are each an integer in 0-255
   (no floats, no negatives, no > 255, no missing channels).
2. Returns `'#rrggbb'` — lowercase, two hex digits per channel, zero-padded
   (`{r: 0, g: 5, b: 16}` -> `'#000510'`).
3. Anything else throws `Error`.

### `mix(a, b, t) -> {r, g, b}`
Linear interpolation between two colors.
Rules (all mandatory):
1. `a` and `b` must be valid RGB objects (integers 0-255 per channel);
   `t` must be a number in `[0, 1]` (inclusive). Otherwise throw `Error`.
2. Each channel: `Math.round(a[ch] + (b[ch] - a[ch]) * t)`.
   `mix(a, b, 0)` returns a copy of `a`'s channels; `mix(a, b, 1)` returns
   b's channels.
3. The result is a NEW object (mutating `a` or `b` must not affect it).

Round-trip: for any valid `c`, `hexToRgb(rgbToHex(c))` deep-equals `c`.

## Test file requirements (`tests/rgb.test.js`)
- `node:test` functions (`const test = require('node:test')`,
  `const assert = require('node:assert/strict')`), run via
  `node --test` (the registry's js stack).
- Import the module: `const { hexToRgb, rgbToHex, mix } = require('../src/rgb.js');`
- The module must be import-safe: no side effects on require, no top-level
  blocking calls (`run.sh smoke` loads it with stdin=/dev/null).
- Cover AT LEAST these cases (write them as explicit assertions):
  - `hexToRgb('#ff8000')` deep-equals `{r: 255, g: 128, b: 0}`
  - `hexToRgb('#000000')` deep-equals `{r: 0, g: 0, b: 0}`
  - `hexToRgb('#FFFFFF')` deep-equals `{r: 255, g: 255, b: 255}` (case-insensitive)
  - `hexToRgb('ff8000')` throws (missing `#`)
  - `hexToRgb('#ff800')` throws (wrong length)
  - `hexToRgb('#gg0000')` throws (non-hex character)
  - `hexToRgb(123)` throws (non-string)
  - `rgbToHex({r: 255, g: 128, b: 0})` equals `'#ff8000'`
  - `rgbToHex({r: 0, g: 5, b: 16})` equals `'#000510'` (zero-padded)
  - `rgbToHex({r: 256, g: 0, b: 0})` throws (out of range)
  - `rgbToHex({r: 1.5, g: 0, b: 0})` throws (non-integer)
  - `rgbToHex({r: 0, b: 0})` throws (missing channel)
  - `mix({r: 0, g: 0, b: 0}, {r: 100, g: 200, b: 300}, 0.5)` deep-equals
    `{r: 50, g: 100, b: 150}`
  - `mix(a, b, 0)` deep-equals `a`'s channels; `mix(a, b, 1)` deep-equals b's
  - `mix(a, b, 1.2)` throws; `mix(a, b, -0.1)` throws
  - round-trip: `const c = {r: 1, g: 254, b: 128};`
    `hexToRgb(rgbToHex(c))` deep-equals `c`

## Deliverables
1. `tests/rgb.test.js` — write FIRST; the red phase (failing test) is
   expected and correct.
2. `src/rgb.js` — implementation (CommonJS, no dependencies).
3. `docs/rgb.md` — one short paragraph describing the module contract.

## Verification
```
bash scripts/run.sh test tests/rgb.test.js
```

Final report (STRICTLY <= 5 lines):
1. TASK: DONE
2. Files: src/rgb.js, tests/rgb.test.js, docs/rgb.md
3. Tests: PASS
