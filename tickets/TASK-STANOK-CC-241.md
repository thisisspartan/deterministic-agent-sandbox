# TASK-STANOK-CC-241 (FIRE-02): Terminal Driver & Half-Block Renderer

impl: src/fire_render.py
test: tests/fire_render_test.py

run.sh: exists

## Context

Second ticket of the DOOMFIRE wave. `src/fire_engine.py` (PALETTE, FireField)
already exists in `src/` — import it, do not modify it. This ticket adds the
terminal driver and the half-block renderer. Pure string building — no process
loop here (that is FIRE-03).

## Requirement

`src/fire_render.py` must provide:

1. Terminal control constants:
   - `ENTER = "\x1b[?1049h\x1b[?25l"` (alternate screen + hide cursor)
   - `EXIT  = "\x1b[?1049l\x1b[?25h\x1b[0m"` (leave alt screen, show cursor,
     reset SGR)

2. A precomputed lookup table `PAIR_CACHE`: for all 37×37 palette index pairs
   (top, bottom) the exact escape string
   `"\x1b[38;2;{tr};{tg};{tb}m\x1b[48;2;{br};{bg};{bb}m▀"`
   built ONCE at import. The hot render path must only join cached strings —
   no f-string formatting per pixel.

3. `render_frame(field) -> str`: one full frame from a FireField-like object
   (attributes `width`, `height`, `buffer`):
   - starts with `"\x1b[H"` (cursor home, no clear);
   - iterates terminal rows as pairs of field rows (top row y, bottom row
     y+1), each terminal row = width cached `▀` cells (fg = color of the top
     field row, bg = color of the bottom field row);
   - ends with `"\x1b[0m"`;
   - rows joined with `"\n"`.

4. `frame_bytes(frame) -> bytes` helper (utf-8 encode) for callers that write
   bytes.

## Tests (`tests/fire_render_test.py`, pytest)

Cover at least: PAIR_CACHE has 1369 entries and a spot-checked entry matches
the exact escape format; `render_frame` on a tiny hand-built field (e.g. 2×2)
produces the exact expected string (cursor home, correct fg/bg codes from
PALETTE, `▀`, final reset); ENTER/EXIT constants exact; cache output equals a
naively formatted reference for a few random pairs (property check with seeded
rng).
