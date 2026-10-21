#!/usr/bin/env bash
# Interactive Claude Code -> local inference server (Strata, qwen3.8-flash-next-iq3_xxs).
# Entry point to an interactive session (grill/coordination) from inside the skeleton.
#
# Portability: NO repo paths. External tools/constants are
# overridden by env (defaults for this machine):
#   STANOK_SERVER_URL  — inference server address (default http://<host>:8080)
#   STANOK_MODEL       — model name (default qwen3.8-flash-next-iq3_xxs)
#   STANOK_PROXY       — proxy for web tooling (default http://<host>:8118)
#   CLAUDE_BIN         — claude binary (default $HOME/.npm-global/bin/claude)
#   SEARCH_ENV_FILE    — optional .env with web-MCP keys (default: none)
#   NO_PROXY_EXTRA     — extra no_proxy entries (default: none)
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
# Token limits — single source of truth: stanok/.claude/settings.stanok.json
# (env block). `--tok` below still overrides the compact window.
STANOK_SETTINGS="$(cd "$(dirname "$0")" && pwd)/stanok/.claude/settings.stanok.json"
[[ -r "$STANOK_SETTINGS" ]] || { printf 'ERROR: %s not found\n' "$STANOK_SETTINGS" >&2; exit 1; }
read -r TOK FILE_READ_OUT MCP_OUT MAX_OUT < <(
    python3 -c 'import json,sys; e=json.load(open(sys.argv[1]))["env"]; print(e["CLAUDE_CODE_AUTO_COMPACT_WINDOW"], e["CLAUDE_CODE_FILE_READ_MAX_OUTPUT_TOKENS"], e["MAX_MCP_OUTPUT_TOKENS"], e["CLAUDE_CODE_MAX_OUTPUT_TOKENS"])' \
        "$STANOK_SETTINGS"
)
[[ -n "$TOK$FILE_READ_OUT$MCP_OUT$MAX_OUT" ]] || { printf 'ERROR: token limits unreadable from %s\n' "$STANOK_SETTINGS" >&2; exit 1; }
ARGS=()
while [[ $# -gt 0 ]]; do
    case "$1" in
        --host)
            HOST="${2:?--host requires an IP address}"
            shift 2
            ;;
        --tok)
            TOK="$2"
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
# Per-value validation (external review 2026-10-16): every token limit must
# be a positive integer. The former non-empty check accepted 0, negatives and
# garbage — a bad value here poisons CLAUDE_CODE_* env and the launcher
# preflight downstream. Covers the --tok override too.
# ---------------------------------------------------------------------------
for _var in TOK FILE_READ_OUT MCP_OUT MAX_OUT; do
    _val="${!_var}"
    if ! [[ "$_val" =~ ^[1-9][0-9]*$ ]]; then
        printf 'ERROR: token limit %s=%s is not a positive integer (source: %s / --tok)\n' \
            "$_var" "$_val" "$STANOK_SETTINGS" >&2
        exit 1
    fi
done

# ---------------------------------------------------------------------------
# External constants (overridable via env)
# ---------------------------------------------------------------------------
SERVER_URL="${STANOK_SERVER_URL:-http://$HOST:8080}"
MODEL="${STANOK_MODEL:-qwen3.8-flash-next-iq3_xxs}"
PROXY="${STANOK_PROXY:-http://$HOST:8118}"
CLAUDE_BIN="${CLAUDE_BIN:-$HOME/.npm-global/bin/claude}"
SEARCH_ENV_FILE="${SEARCH_ENV_FILE:-}"

# Propagate the endpoint to the machine: stanok/launcher/stanok.py reads
# STANOK_SERVER_URL / STANOK_PROXY from the environment (default 127.0.0.1).
export STANOK_SERVER_URL="$SERVER_URL"
export STANOK_PROXY="$PROXY"

# ---------------------------------------------------------------------------
# Preflight against the EFFECTIVE server (same semantics as the machine's
# launcher preflight, for the interactive path): the required window (TOK)
# must fit inside the server's live n_ctx — fail-closed; a model identity
# mismatch is an explicit warning here, not a hard stop. STANOK_SKIP_SERVER_CHECK=1
# skips, as in launcher/gates.py.
# ---------------------------------------------------------------------------
if [[ "${STANOK_SKIP_SERVER_CHECK:-}" != "1" ]]; then
    if ! python3 - "$SERVER_URL" "$MODEL" "$TOK" <<'PY'
import json, os, sys, urllib.request
url, model, tok = sys.argv[1], sys.argv[2], int(sys.argv[3])
try:
    opener = urllib.request.build_opener(urllib.request.ProxyHandler({}))
    with opener.open(url.rstrip("/") + "/props", timeout=5) as resp:
        props = json.loads(resp.read().decode("utf-8", "replace"))
except Exception as e:
    print(f"ERROR: cannot read {url}/props: {e}", file=sys.stderr)
    sys.exit(1)
n_ctx = (props.get("default_generation_settings") or {}).get("n_ctx")
if not isinstance(n_ctx, int) or n_ctx <= 0:
    print(f"ERROR: server {url} exposes no usable n_ctx", file=sys.stderr)
    sys.exit(1)
if n_ctx < tok:
    print(f"ERROR: server n_ctx={n_ctx} < required window {tok} "
          f"(--tok / settings CLAUDE_CODE_AUTO_COMPACT_WINDOW)", file=sys.stderr)
    sys.exit(1)
ids = []
alias = props.get("model_alias")
if isinstance(alias, str) and alias.strip():
    ids.append(alias.strip())
aliases = props.get("model_path_aliases")
if isinstance(aliases, list):
    ids.extend(a.strip() for a in aliases if isinstance(a, str) and a.strip())
path = props.get("model_path")
if isinstance(path, str) and path.strip():
    stem = os.path.splitext(os.path.basename(path.strip()))[0]
    if stem:
        ids.append(stem)
if ids and all(i.lower() != model.lower() for i in ids):
    print(f"WARNING: server model {ids[0]!r} != configured STANOK_MODEL {model!r}",
          file=sys.stderr)
PY
    then
        exit 1
    fi
fi

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
    no_proxy="127.0.0.1,localhost"
else
    no_proxy="$HOST,localhost,127.0.0.1"
fi
# The EFFECTIVE server host: when STANOK_SERVER_URL overrides to a host
# other than $HOST (e.g. a LAN host), model traffic to it must
# bypass the proxy too — no_proxy built from $HOST alone would proxy it.
server_host="${SERVER_URL#*://}"
server_host="${server_host%%/*}"
server_host="${server_host%%:*}"
if [[ -n "$server_host" && ",$no_proxy," != *",$server_host,"* ]]; then
    no_proxy="$no_proxy,$server_host"
fi
# Machine-specific extra entries (e.g. a docker-host LAN IP) go here via env,
# not in the script: the public skeleton carries no local addresses.
[[ -n "${NO_PROXY_EXTRA:-}" ]] && no_proxy="$no_proxy,$NO_PROXY_EXTRA"
export no_proxy
export NO_PROXY="$no_proxy"

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
# Context / compaction (Strata backend since 2026-10-08: max-context 131072; window 131000)
# Token limits come from $STANOK_SETTINGS (read at the top of this script).
# ---------------------------------------------------------------------------
export CLAUDE_CODE_AUTO_COMPACT_WINDOW="$TOK"
export STANOK_REQUIRED_WINDOW="$TOK"
export CLAUDE_AUTOCOMPACT_PCT_OVERRIDE="95"
export CLAUDE_CODE_FILE_READ_MAX_OUTPUT_TOKENS="$FILE_READ_OUT"
export MAX_MCP_OUTPUT_TOKENS="$MCP_OUT"
export API_TIMEOUT_MS="600000"
export CLAUDE_CODE_MAX_OUTPUT_TOKENS="$MAX_OUT"
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
# Pre-flight: verify the local inference server endpoint
# ---------------------------------------------------------------------------
MODEL_NAME="?"
SERVER_CTX="?"
SERVER_SLOTS="?"
if [[ "${STANOK_SKIP_SERVER_CHECK:-}" == "1" ]]; then
    MODEL_LINE="? (server check skipped)"
else
    PROPS="$(curl -s --noproxy '*' --max-time 5 "$SERVER_URL/props" 2>/dev/null || true)"
    if [[ -z "$PROPS" ]]; then
        printf '\033[31mERROR: local inference server is unavailable @ %s\033[0m\n' \
            "$SERVER_URL" >&2
        printf '\033[33mStart the inference server first, or set STANOK_SKIP_SERVER_CHECK=1.\033[0m\n' \
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
ROLE_ROOT="$(cd "$(dirname "$0")" && pwd)"
ROLE_SRC="$ROLE_ROOT/CLAUDE.supervisor.md"
if [[ -f "$ROLE_SRC" ]]; then
    # The tracked role file is path-agnostic: `<project-root>` placeholders —
    # the public tree must not carry this machine's absolute paths (2026-10-21).
    # Rendered HERE, the role file's only consumer: the placeholder becomes the
    # real absolute root in a temp copy; §3/§4 paths are absolute at use time.
    ROLE_FILE="$(mktemp "${TMPDIR:-/tmp}/stanok-role.XXXXXX")"
    sed "s|<project-root>|$ROLE_ROOT|g" "$ROLE_SRC" > "$ROLE_FILE"
    exec "$CLAUDE_BIN" --append-system-prompt-file "$ROLE_FILE" "$@"
fi
exec "$CLAUDE_BIN" "$@"
