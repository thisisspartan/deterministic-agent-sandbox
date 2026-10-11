# TASK-STANOK-CC-240 (FIRE-01): Palette & Math Engine — pure Doom Fire logic, no I/O

impl: src/fire_engine.py
test: tests/fire_engine_test.py

run.sh: exists

## Context

First ticket of the DOOMFIRE wave (see the algorithm contract below — it is
the spec, follow it exactly). This ticket is the pure engine: palette + fire
matrix + `step`. No terminal codes, no I/O, no rendering here.

## Requirement

`src/fire_engine.py` must provide:

1. `PALETTE`: exactly 37 RGB tuples — the classic Doom fire palette:
   (0x07,0x07,0x07),(0x1F,0x07,0x07),(0x2F,0x0F,0x07),(0x47,0x0F,0x07),
   (0x57,0x17,0x07),(0x67,0x1F,0x07),(0x77,0x1F,0x07),(0x8F,0x27,0x07),
   (0x9F,0x2F,0x07),(0xAF,0x3F,0x07),(0xBF,0x47,0x07),(0xC7,0x47,0x07),
   (0xDF,0x4F,0x07),(0xDF,0x57,0x07),(0xDF,0x57,0x07),(0xD7,0x5F,0x07),
   (0xD7,0x67,0x0F),(0xCF,0x6F,0x0F),(0xCF,0x77,0x0F),(0xCF,0x7F,0x0F),
   (0xCF,0x87,0x17),(0xC7,0x87,0x17),(0xC7,0x8F,0x17),(0xC7,0x97,0x1F),
   (0xBF,0x9F,0x1F),(0xBF,0x9F,0x1F),(0xBF,0xA7,0x27),(0xBF,0xA7,0x27),
   (0xBF,0xAF,0x2F),(0xB7,0xAF,0x2F),(0xB7,0xB7,0x2F),(0xB7,0xB7,0x37),
   (0xCF,0xCF,0x6F),(0xDF,0xDF,0x9F),(0xEF,0xEF,0xC7),(0xFF,0xFF,0xFF),
   (0xFF,0xFF,0xFF)

2. `class FireField(width, height, rng=None)`: flat buffer
   `buffer[y * width + x]`, y=0 top, y=height-1 is the source row, seeded to
   36. `rng` is an injectable `random.Random` (default module random) so tests
   are deterministic.

3. `step(wind=0)` — the exact propagation (single bottom-up pass):
   for y from height-1 down to 1, for each x:
   - src = buf[y][x]; if src == 0 → buf[y-1][x] = 0
   - else: rand = rng-based int in [0..3]; dst = x - rand + 1 + wind;
     if 0 <= dst < width: buf[y-1][dst] = max(0, src - (rand & 1))
     (out-of-bounds dst: skip, no wrap).
   - `wind` is clamped to [-3, 3].

4. `color_at(value)` → PALETTE[value] (value is always 0..36 by construction).

No terminal escape codes, no file/socket I/O in this module.

## Tests (`tests/fire_engine_test.py`, pytest)

Cover at least: palette length 37 and first/last entries; source row seeded to
36; with a seeded rng a known small field propagates to exact expected values
(pin the rng seed and assert the exact resulting row); decay never goes below
0; wind shifts the source index symmetrically; zero pixels stay zero;
color_at bounds. Use a seeded `random.Random` everywhere — no flaky asserts.
