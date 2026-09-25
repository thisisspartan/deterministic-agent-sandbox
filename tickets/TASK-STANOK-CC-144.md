# TASK-STANOK-CC-144 — cli.js correctness & dead code (STANOK_TEMP, think_off, effort, globals)

Supervisor-executed in the **CLI repo** (`~/git/claude-code-2.1.88`), branch
`base`. No machine launch. Part of `specs/PLAN-cli-js-hygiene-2026-09-25.md`
(F3–F6). **Changes the bundle → needs one live smoke before it is trusted.**
Gate: CC-143 (`patches/verify.sh`) landed first.

## Findings

- **F3 (bug).** `let j1=!W6?$.temperatureOverride??(parseFloat(process.env.STANOK_TEMP)||1):void 0`
  (line 7843). `parseFloat("0")` is `0` → falsy → **`1`**. Temperature `0` is
  inexpressible, and an invalid value is silently coerced to `1` instead of
  falling back loudly.
- **F4.** `<|think_off|>` appears as a **literal prompt string** at 3 live sites:
  `oWK` preamble, `aWK`, and the summarizer `systemPrompt`
  (`["You are a helpful AI assistant tasked with summarizing conversations.","<|think_off|>"]`).
  If the model's chat template does not treat the marker specially it is plain
  prompt text — an undocumented coupling to the template that drifts silently.
- **F5.** `/effort` notification is suppressed by gutting `PvK`:
  `function PvK(q,K){return}` (helpers `P78` still present), while the call site
  still computes `jx=F6?void 0:PvK(H8,j6)` and gates a `useEffect`.
- **F6.** `globalThis.__phase/__in/__out/__lt/__ltt/__t_decode/__end` — mutable
  global state written/read at ~8 sites (lines 2161, 2203, 4181/4183, 4824, 7843).
  History already records two fixes from this coupling (`2161933` `__ft`
  deadlock; `12d0e9c` double `__lt` tap garbling the ∴ line).

## Change

- **F3:** `const t=parseFloat(process.env.STANOK_TEMP); … Number.isFinite(t)?t:1`.
  `0` and `0.2` both reach the request body.
- **F4:** one shared constant/helper for the marker; the 3 sites reference it.
  Document in `patches/PATCHES.md` **and** in the plan: the marker is literal
  prompt text unless the chat template handles it — state the coupling
  explicitly (this is the `think_off`↔template contract from the B-series work).
- **F5:** delete the empty `PvK`/`P78` and the now-purpose-less call site, or
  restore the notification — pick one, do not leave a half-dead branch.
- **F6:** factor the `globalThis.__*` writes into one inline helper (single
  entry point for the phase machine); optional env gate
  (`STANOK_SPINNER_TRACE=0`) to disable it for headless runs.

## Verification

- `bash patches/verify.sh` (CC-143) → 0 with updated anchors; `node --check cli.js`.
- **STANOK_TEMP e2e:** live run with `STANOK_TEMP=0` → the server log / a mock
  capture shows `temperature=0` in the request body (upstream default is `0.2`;
  the bundle default stays `1` unless the operator rules otherwise — CC-145 #4).
- Spinner smoke: a live run shows PREFILL/THINKING/DECODE progression and the ∴
  line unchanged vs the current bundle.
- `git rev-parse base:cli.js` will move (this ticket edits the bundle) — record
  the new blob and update `setup.sh:42 CLI_JS_SHA` accordingly.

## Non-goals / residuals

- Not a spinner redesign: no behavior change to what is displayed, only how the
  state is stored.
- `<|think_off|>` semantics on the model side (does the template honor it?) is a
  documentation/contract question — this ticket does not change the template.
