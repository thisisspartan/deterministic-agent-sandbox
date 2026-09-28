# TASK-STANOK-CC-171: smoke geometry utilities

impl: src/smoke_geom.py
test: tests/smoke_geom_test.py
run.sh: exists

## Task

Implement small 2D geometry utilities in `src/smoke_geom.py` (pure stdlib, no
third-party imports) and cover them with pytest in `tests/smoke_geom_test.py`.

Points are 2-tuples of numbers, e.g. `(0.0, 0.0)`.

Functions:

1. `distance(p1, p2) -> float` — Euclidean distance between two points.
   `distance((0, 0), (3, 4)) == 5.0`.
2. `midpoint(p1, p2) -> tuple` — the midpoint as a 2-tuple of floats.
   `midpoint((0, 0), (4, 6)) == (2.0, 3.0)`.
3. `triangle_area(a, b, c) -> float` — area of the triangle with vertices
   `a`, `b`, `c` via the shoelace formula (always non-negative).
   Collinear points give `0.0`. `triangle_area((0, 0), (4, 0), (0, 3)) == 6.0`.

## Requirements

- No network, no files, no global state.
- All functions accept 2-tuples of ints or floats and are total (no
  exceptions for any such input).
- Return types exactly as specified (float / tuple of floats).

## Acceptance criteria

- `bash scripts/run.sh test` passes with the new tests green.
- `tests/smoke_geom_test.py` covers: distance (integer 3-4-5, zero distance,
  negative coordinates, float inputs), midpoint (int inputs → float tuple,
  negative coordinates, identical points), triangle area (right triangle,
  collinear → 0.0, vertex order independence, float inputs).
