#!/usr/bin/env bash
# Interactive Claude Code -> local llama-server (Qwen3.8-27B-MTP).
# Entry point to an interactive session (grill/coordination) from inside the skeleton.
#
# Portability: NO repo paths. External tools/constants are
# overridden by env (defaults for this machine):
#   STANOK_SERVER_URL  — llama-server address (default http://<host>:8080)
#   STANOK_MODEL       — model name (default Qwen3.8-27B-MTP)
#   STANOK_PROXY       — proxy for web tooling (default http://<host>:8118)
#   CLAUDE_BIN         — claude binary (default $HOME/.npm-global/bin/claude)
#   SEARCH_ENV_FILE    — .env with web-MCP keys (default $HOME/git/agnt/.env)
#
# Run: ./P0-launch.sh [--host <ip>] [claude arguments]
set -u
set -o pipefail

# ---------------------------------------------------------------------------
# Host flag: the inference-server host (no hardcoded IP).
# --host <ip> sets the server host; env overrides (STANOK_SERVER_URL /
# STANOK_PROXY) still win. All other arguments pass through to claude.
# ---------------------------------------------------------------------------
HOST="127.0.0.1"
ARGS=()
while [[ $# -gt 0 ]]; do
    case "$1" in
        --host)
            HOST="${2:?--host requires an IP address}"
            shift 2
            ;;
        *)
            ARGS+=("$1")
            shift
            ;;
    esac
done
set -- "${ARGS[@]}"

# ---------------------------------------------------------------------------
# External constants (overridable via env)
# ---------------------------------------------------------------------------
SERVER_URL="${STANOK_SERVER_URL:-http://$HOST:8080}"
MODEL="${STANOK_MODEL:-Qwen3.8-27B-MTP}"
PROXY="${STANOK_PROXY:-http://$HOST:8118}"
CLAUDE_BIN="${CLAUDE_BIN:-$HOME/.npm-global/bin/claude}"
SEARCH_ENV_FILE="${SEARCH_ENV_FILE:-$HOME/git/agnt/.env}"

# Propagate the endpoint to the machine: stanok/launcher/stanok.py reads
# STANOK_SERVER_URL / STANOK_PROXY from the environment (default 127.0.0.1).
export STANOK_SERVER_URL="$SERVER_URL"
export STANOK_PROXY="$PROXY"

# ---------------------------------------------------------------------------
# Local Anthropic-compatible endpoint
# ---------------------------------------------------------------------------
export ANTHROPIC_BASE_URL="$SERVER_URL"
export ANTHROPIC_AUTH_TOKEN="local-dummy"
# Empty API key prevents API-key authentication from taking precedence.
export ANTHROPIC_API_KEY=""

# Keep every Claude Code model role on the same local model.
export ANTHROPIC_MODEL="$MODEL"
export ANTHROPIC_DEFAULT_SONNET_MODEL="$MODEL"
export ANTHROPIC_DEFAULT_OPUS_MODEL="$MODEL"
export ANTHROPIC_DEFAULT_HAIKU_MODEL="$MODEL"
export CLAUDE_CODE_SUBAGENT_MODEL="$MODEL"

# ---------------------------------------------------------------------------
# Network
# ---------------------------------------------------------------------------
# Proxies are for external/web tooling only. Local server is excluded.
export http_proxy="$PROXY"
export https_proxy="$PROXY"
export all_proxy=""
if [[ "$HOST" == "127.0.0.1" ]]; then
    export no_proxy="127.0.0.1,localhost"
else
    export no_proxy="$HOST,localhost,127.0.0.1"
fi

# ---------------------------------------------------------------------------
# Local / offline-friendly Claude Code behavior
# ---------------------------------------------------------------------------
export DISABLE_AUTOUPDATER="1"
export CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC="1"
export CLAUDE_CODE_DISABLE_EXPERIMENTAL_BETAS="1"
export CLAUDE_CODE_ATTRIBUTION_HEADER="0"
export CLAUDE_CODE_DISABLE_1M_CONTEXT="1"
export CLAUDE_CODE_DISABLE_ADVISOR_TOOL="1"
export CLAUDE_CODE_DISABLE_GIT_INSTRUCTIONS="1"
export CLAUDE_CODE_DISABLE_AUTO_MEMORY="1"

# ---------------------------------------------------------------------------
# Context / compaction (n_ctx=123136, output reserve 24k)
# Canon: 123000/12000/20000 — keep in sync with stanok/.claude/settings.stanok.json
# ---------------------------------------------------------------------------
export CLAUDE_CODE_AUTO_COMPACT_WINDOW="123000"
export CLAUDE_AUTOCOMPACT_PCT_OVERRIDE="95"
export CLAUDE_CODE_FILE_READ_MAX_OUTPUT_TOKENS="16000"
export MAX_MCP_OUTPUT_TOKENS="12000"
export API_TIMEOUT_MS="600000"
export CLAUDE_CODE_MAX_OUTPUT_TOKENS="20000"
export CLAUDE_CODE_MAX_CONCURRENT_SUBAGENTS="1"
export CLAUDE_CODE_DISABLE_ADAPTIVE_THINKING=1
# ---------------------------------------------------------------------------
# Side-call / retry hygiene (single-slot local endpoint)
# ---------------------------------------------------------------------------
export CLAUDE_CODE_DISABLE_TERMINAL_TITLE="1"
export CLAUDE_CODE_DISABLE_NONSTREAMING_FALLBACK="1"
export CLAUDE_CODE_MAX_RETRIES="2"
export CLAUDE_CODE_ENABLE_PROMPT_SUGGESTION="0"

# ---------------------------------------------------------------------------
# Local-model / subagent concurrency (one inference slot)
# ---------------------------------------------------------------------------
export BASH_MAX_OUTPUT_LENGTH="8000"

# ---------------------------------------------------------------------------
# Web-search MCP credentials: inherit into stdio MCP subprocesses
# ---------------------------------------------------------------------------
SEARCH_KEY_COUNT=""
if [[ -r "$SEARCH_ENV_FILE" ]]; then
    SEARCH_KEYS="$(
        grep -E '^(SERPER_KEY[0-2]|TAVILY_KEY[0-2]|EXA_KEY[0-2])=' \
        "$SEARCH_ENV_FILE" 2>/dev/null || true
    )"
    if [[ -n "$SEARCH_KEYS" ]]; then
        while IFS='=' read -r k v; do
            [[ -n "$k" ]] && export "$k=$v"
        done <<< "$SEARCH_KEYS"
        SEARCH_KEY_COUNT="$(printf '%s\n' "$SEARCH_KEYS" | grep -c . || true)"
    fi
fi

# ---------------------------------------------------------------------------
# Pre-flight: verify the local llama-server endpoint
# ---------------------------------------------------------------------------
MODEL_NAME="?"
SERVER_CTX="?"
SERVER_SLOTS="?"
if [[ -n "${STANOK_SKIP_SERVER_CHECK:-}" ]]; then
    MODEL_LINE="? (server check skipped)"
else
    PROPS="$(curl -s --noproxy '*' --max-time 5 "$SERVER_URL/props" 2>/dev/null || true)"
    if [[ -z "$PROPS" ]]; then
        printf '\033[31mERROR: local llama-server is unavailable @ %s\033[0m\n' \
            "$SERVER_URL" >&2
        printf '\033[33mStart llama-server first, or set STANOK_SKIP_SERVER_CHECK=1.\033[0m\n' \
            >&2
        exit 1
    fi
    if command -v python3 >/dev/null 2>&1; then
        read -r MODEL_NAME SERVER_CTX SERVER_SLOTS < <(
            printf '%s' "$PROPS" |
            python3 -c '
import json, sys
d=json.load(sys.stdin)
g=d.get("default_generation_settings", {})
print(
    d.get("model_alias", "?"),
    g.get("n_ctx", d.get("n_ctx", "?")),
    d.get("total_slots", "?")
)'
        ) || { MODEL_NAME="?"; SERVER_CTX="?"; SERVER_SLOTS="?"; }
    fi
    MODEL_LINE="$MODEL_NAME @ $SERVER_URL (n_ctx=$SERVER_CTX slots=$SERVER_SLOTS)"
fi

echo "Local Claude Code -> $MODEL"
echo "  endpoint : $ANTHROPIC_BASE_URL"
echo "  model    : $MODEL"
echo "  server   : $MODEL_LINE"
echo "  context  : $CLAUDE_CODE_AUTO_COMPACT_WINDOW"
echo "  compact  : ${CLAUDE_AUTOCOMPACT_PCT_OVERRIDE}%"
echo "  subagents: max ${CLAUDE_CODE_MAX_CONCURRENT_SUBAGENTS}"
if [[ -n "$SEARCH_KEY_COUNT" ]]; then
    echo "  web MCP  : provider keys loaded ($SEARCH_KEY_COUNT entries)"
fi

# ---------------------------------------------------------------------------
# Control-room supervisor role (L1).
# The parent CLAUDE.md is renamed to CLAUDE.supervisor.md: otherwise Claude Code
# would auto-load it into the machine as well (cwd=stanok — a subdirectory of the
# project root), and the machine would start thinking it is the "L1 supervisor"
# (role leak). The control room now receives the role EXPLICITLY, as a file,
# not via auto-loading.
# ---------------------------------------------------------------------------
ROLE_FILE="$(cd "$(dirname "$0")" && pwd)/CLAUDE.supervisor.md"
if [[ -f "$ROLE_FILE" ]]; then
    exec "$CLAUDE_BIN" --append-system-prompt-file "$ROLE_FILE" "$@"
fi
exec "$CLAUDE_BIN" "$@"
