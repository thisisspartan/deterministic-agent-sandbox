# TASK-STANOK-CC-064 — Fire realism 4/4: heat-scaled inertia (lively tips)

## Background / problem
The terminal fire (Doom-fire port) now looks good overall, but the **top of the
flame looks frozen after a while** — the tips go static while the lower, hotter
part keeps flickering.

Root cause: the existing `inertia` option is a **uniform** temporal low-pass
filter (`v = inertia*old + (1-inertia)*v`). It smooths every cell by the same
amount. The top rows are cold (low heat) and already change very little per
frame, so the uniform smoothing removes almost all of their remaining variation
→ the tips look frozen. The hot core changes a lot, so even after smoothing it
still looks lively. Real flame tips are the most unstable/flickery part, so the
smoothing should be **weaker where the cell is cold** and **stronger where it is
hot**.

## Goal
Add an opt-in **heat-scaled inertia** so the effective inertia is scaled by the
cell's own heat: cold tips keep high-frequency flicker, the hot core stays
smooth. This must be a new, backward-compatible option — with it off, the model
is bit-identical to today (all existing tests keep passing).

## Scope (work ONLY in these three files)
- `src/fire_model.js`
- `tests/fire_model.test.js`
- `docs/fire.md`
- `src/main.js` (app wiring only — see below)
- `tests/fire_app.test.js` (app tests only)

Do NOT touch `src/fire_render.js` or `tests/fire_render.test.js`.
Do NOT delete or weaken any existing test. Extend the test files only.
Do NOT create new files or add npm dependencies. Use only built-in Node modules.

## 1. `src/fire_model.js` — new opt `heatInertia`

Add one new option to `createFireModel(w, h, opts)`:

- `heatInertia` — **boolean**, default `false`.
  - `false` (default): the current **uniform** inertia blend, unchanged. This
    keeps the model bit-identical to today, so every existing test passes.
  - `true`: **heat-scaled** inertia blend (see reference below).

### Validation
Validate `heatInertia` up front, alongside the other opts:
- If `opts.heatInertia === undefined` → `heatInertia = false`.
- Otherwise it MUST be a boolean; any non-boolean value throws `TypeError`
  (message: `'heatInertia must be a boolean'`).

### Reference algorithm (inside `step()`)
Replace the current inertia branch:

```js
if (inertia > 0) {
  v = inertia * grid[y][x] + (1 - inertia) * v; // grid[y][x] is the OLD value
}
```

with:

```js
if (inertia > 0) {
  const old = grid[y][x];                       // OLD value (double-buffered read)
  const eff = heatInertia ? inertia * (old / maxHeat) : inertia;
  v = eff * old + (1 - eff) * v;
}
```

Properties that must hold (and are worth asserting in tests):
- `eff` is in `[0, inertia)` ⊂ `[0, 1)`, so `eff*old + (1-eff)*v` is a convex
  combination of two values already in `[0, maxHeat]` → the result stays in
  `[0, maxHeat]` (the existing clamp still applies and is unchanged).
- The PRNG call order is **unchanged** (the inertia branch consumes no `rand()`),
  so determinism per seed+opts is preserved and the legacy-identity test
  (inertia=0) is unaffected.
- Cold cell (`old ≈ 0`) → `eff ≈ 0` → almost no smoothing (lively flicker).
  Hot cell (`old ≈ maxHeat`) → `eff ≈ inertia` → full smoothing (smooth core).

## 2. `src/main.js` — wire `heatInertia` into `createApp`

- Add `heatInertia` to `createApp(opts)` with a **default of `true`** (the
  default app renders the more realistic, lively-tips fire).
- Forward it to the heat model: include `heatInertia` in the `modelOpts` object
  passed to `createFireModel` (alongside `inertia` and `turbulence`).
- Expose it on the returned object so the default/override is observable:
  `{ w, h, fps, maxHeat, inertia, turbulence, density, heatInertia, start, stop }`.
- Headless (non-TTY) behavior is unchanged: still the escape-free `symbols`
  palette. `heatInertia` only affects the model, not the renderer.

## 3. Tests — EXTEND, do not delete or weaken existing tests

### `tests/fire_model.test.js` — add these tests (keep all existing ones):
1. **heatInertia=true is deterministic**: two models with the same seed and
   `{ inertia: 0.5, turbulence: 0, heatInertia: true }` produce identical grids
   after 50 steps (`assert.deepStrictEqual`).
2. **heatInertia=true range invariant**: a model with
   `{ seed, inertia: 0.5, turbulence: 0.5, heatInertia: true }` stays within
   `[0, maxHeat]` for all cells after 100 steps (reuse the existing
   `assertInRange` helper).
3. **livelier tips (the key behavioral test)**: measure the **top-third mean
   per-step delta** (mean over the top `floor(h/3)` rows of the mean absolute
   per-cell change between consecutive frames, after a warmup). With
   `inertia: 0.5, turbulence: 0`:
   - model A: `heatInertia: false`
   - model B: `heatInertia: true`
   Assert `topDelta(B) > topDelta(A)`.
   (Rationale: heat-scaled inertia smooths the cold top rows far less than
   uniform inertia, so their frame-to-frame change is larger. Use the same
   warmup/frames scale as the existing "inertia smooths" test, e.g. warmup 200,
   frames 50, on a grid like 40x24 with a fixed seed.)
4. **heatInertia=false is bit-identical to the current uniform behavior**: an
   inline reference implementation of the CURRENT uniform-inertia step
   (inertia=0.5, turbulence=0) must match a model created with
   `{ seed, inertia: 0.5, turbulence: 0, heatInertia: false }` after 1 step
   (mirror the existing "legacy identity" test structure, but with the uniform
   inertia blend included). This guards backward compatibility.
5. **invalid heatInertia throws TypeError**: `createFireModel(10, 10, { heatInertia: 1 })`,
   `{ heatInertia: 'x' }`, `{ heatInertia: null }` each throw `TypeError`.

### `tests/fire_app.test.js` — add these tests (keep all existing ones):
1. **heatInertia defaults to true**: `createApp({})` returns an object whose
   `heatInertia === true` (extend the existing "realistic defaults" assertion or
   add a sibling test).
2. **override honored**: `createApp({ heatInertia: false })` returns
   `heatInertia === false`; `createApp({ heatInertia: true })` returns `true`.
3. **headless frames stay clean under the new default**: with default opts
   (which now include `heatInertia: true`), headless (non-TTY) frames contain no
   terminal escapes (extend/reuse the existing headless-clean test).

## 4. `docs/fire.md` — document the new option
Add a short section describing `heatInertia`:
- Model: opt-in boolean, default `false` (uniform inertia, bit-identical to
  before); `true` scales the effective inertia by the cell's heat
  (`eff = inertia * old / maxHeat`) so cold tips flicker and the hot core stays
  smooth.
- App: `createApp` defaults `heatInertia` to `true` (realistic lively tips),
  overridable, exposed on the returned object.

## Acceptance criteria
- `bash scripts/run.sh test tests/fire_model.test.js tests/fire_render.test.js tests/fire_app.test.js`
  is fully green (all existing tests + all new tests pass).
- With `heatInertia` off (model default) the model output is bit-identical to
  today (no existing test changes behavior).
- No new files, no npm dependencies, no changes to `fire_render.js` or its tests.

## Final report (STRICTLY ≤ 5 lines)
1. TASK: DONE
2. Files: src/fire_model.js, src/main.js, tests/fire_model.test.js, tests/fire_app.test.js, docs/fire.md
3. Tests: PASS
