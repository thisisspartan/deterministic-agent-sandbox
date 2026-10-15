# patches/ — pinned out-of-tree patches (CC-153)

Same pattern as the planned cli.js `patches/` line (CC-143): a patch lives
here under version control, pinned to an exact upstream commit, with the
build/launch contract documented next to it.

## 0001-llama-server-tool_choice-object.patch

- **Target:** llama.cpp `tools/server/server-common.cpp`,
  `oaicompat_chat_params_parse()` — maps the OpenAI **object form** of
  `tool_choice` (`{"type":"function","function":{...}}`) to the string
  forms the sampling layer knows: `none`→`none`, `auto` (or no tools)→
  `auto`, anything else (`function`/`any`/`tool`)→`required`.
- **Why it matters:** the pinned cli.js (`~/git/claude-code-2.1.88/cli.js`,
  `base`) emits object-form `tool_choice` (`tool_choice:{type:"tool"…}`,
  `tool_choice:$.toolChoice`) — without the patch the server's
  `json_value(body, "tool_choice", std::string("auto"))` misreads it.
- **Pinned commit:** `e2d2c0d6a` (`v0.4.0-65-ge2d2c0d6a`), the llama.cpp
  tree at `/home/llm/llama.cpp` on 192.168.8.131 (branch `master`, clean
  tree). Verified 2026-09-25: `git apply --check` → **applies clean** at
  the pinned commit.
- **Build recipe (as built 2026-09-22):** `cmake -G Ninja
  -DCMAKE_BUILD_TYPE=Release -DGGML_CUDA=ON` + `ninja` (RTX 5060 Ti,
  driver 595.84); binary `build/bin/llama-server` (thin launcher +
  `libllama-server-impl.so`).
- **Server launch flags (live, captured 2026-09-25):**
  ```
  llama-server -m /data/models/Qwen3.8-27B-GSQ-RCO-IQ3_S-mtp.gguf \
    --alias Qwen3.8-27B-MTP -ngl 99 --threads 8 --threads-batch 8 -fa on \
    --parallel 1 -c 123000 -b 1024 -ub 128 --cache-type-k q4_0 \
    --cache-type-v q4_0 --ctx-checkpoints 24 --checkpoint-min-step 4096 \
    --cache-ram 30720 --seed 42 --spec-type draft-mtp,ngram-mod \
    --spec-draft-n-max 6 --spec-draft-p-min 0.70 --temp 0.2 --top-p 0.95 \
    --top-k 40 --min-p 0.01 --repeat-penalty 1.0 --repeat-last-n 512 \
    --reasoning on --jinja \
    --chat-template-file /data/models/chat_template.jinja.new \
    --chat-template-kwargs {"reasoning_effort":"medium","preserve_thinking":true,"max_tool_response_chars":20000} \
    --metrics --host 0.0.0.0 --port 8080 -lv 4
  ```

## Chat-template marker contract (cli.js ⇄ template)

The typed contract between cli.js and the remote template
(`/data/models/chat_template.jinja.new`, qwen3.8-froggeric-v22.1):

- cli.js emits the literal markers `<|think_off|>` / `<|think_on|>`
  (preamble `oWK`, `aWK`, summarizer system prompt — see
  `specs/PLAN-cli-js-hygiene-2026-09-25.md` §2-B).
- The template interprets them at: lines 38/40 and 62/64 (per-message /
  per-tool-item think toggle), 146–147 and 205–206 (strip markers from
  system/content text), 362–380 (system + last-reasoning-content logic).
- If either side drifts (marker renamed on one side only), thinking
  control silently breaks — this file is the in-repo record of the
  coupling.

## cli.js line: `STANOK_TEMP` → request temperature (CC-266, 2026-10-15)

- **Target:** the pinned cli.js (`~/git/claude-code-2.1.88/cli.js`, branch
  `base`, HEAD `c306331`) — out-of-tree patch, not in this repo's tree.
- **What it does:** non-thinking API requests send `temperature =
  parseFloat(process.env.STANOK_TEMP)` (default 1) instead of the hardcoded
  `temperature: 1`. Introduced in `09fc14f` (2026-09-24), verified there via
  mock capture (`STANOK_TEMP=0.2` → request body `temperature=0.2`).
- **Live contract:** `stanok/.claude/settings.stanok.json` env
  `STANOK_TEMP = "0.0"` (operator decision 2026-09-29: greedy decoding for
  the machine). `parseFloat("0.0")` is safe — no falsy branch.
- **Status:** documented, not re-applied here — the consumer is the patched
  cli.js outside the repo; no code change in darkcast/stanok.

## FINDING (2026-09-25, for the operator)

The **currently running** server (binary built 2026-09-22 10:39, process
started 2026-09-25 10:04) does **NOT** contain this patch: the tree is
clean at `e2d2c0d6a` and the string `tool_choice object` is absent from
`libllama-server-impl.so`. The patch was evidently lost in the 2026-09-22
rebuild. Applying it = re-apply + rebuild + restart of the live inference
server — an operator decision; per operator instruction (2026-09-25) the
remote server is not to be touched or restarted.

## Deferred (needs remote access, frozen by operator 2026-09-25)

- `verify.sh` (CC-143 pattern): would re-run `git apply --check` of this
  patch at the pinned commit on the remote tree and fail non-zero on
  drift. Not added while SSH to 192.168.8.131 is frozen.
