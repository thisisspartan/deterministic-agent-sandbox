#!/usr/bin/env bash
# destructive-guard.sh — PreToolUse hook (Bash) для супервайзера.
# Блокирует деструктивные команды, которые не должны выполняться супервайзером:
#   - rm -rf /  и rm -rf ~  (и варианты: $HOME, /*, -fr, -r -f)
#   - git reset --hard
#   - git push --force / -f
#   - git clean -fd / -fdx / -fdq
# Протокол: stdin = JSON вызова; stdout = hookSpecificOutput с permissionDecision.
# Exit 0 + deny-JSON = блокировка. Exit 0 + без deny = allow.
set -euo pipefail

INPUT="$(cat)"
CMD="$(printf '%s' "$INPUT" | python3 -c "
import json,sys
try:
    d=json.load(sys.stdin)
    print(d.get('tool_input',{}).get('command',''))
except Exception:
    print('')
")"

[ -n "$CMD" ] || exit 0   # нет command — не наш случай

deny() {
  printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"destructive-guard: %s"}}' "$1"
  exit 0
}

# --- rm -rf / и rm -rf ~ ---
# Поймает: rm -rf /, rm -rf /*, rm -rf ~, rm -rf $HOME, rm -fr /, rm -r -f /
# Флаги: -rf, -fr, -r -f, -Rf, -fR и т.д. — ищем rm + флаги с r и f + путь / или ~
if printf '%s' "$CMD" | grep -qE 'rm\s+(-[a-zA-Z]*[rf][a-zA-Z]*\s+)+/(\s|$|/)' || \
   printf '%s' "$CMD" | grep -qE 'rm\s+(-[a-zA-Z]*[rf][a-zA-Z]*\s+)+~(\s|$)' || \
   printf '%s' "$CMD" | grep -qE 'rm\s+(-[a-zA-Z]*[rf][a-zA-Z]*\s+)+\$HOME'; then
  deny "rm -rf на корневой/домашний путь: $CMD"
fi

# --- git reset --hard ---
if printf '%s' "$CMD" | grep -qE 'git\s+reset\s+--hard'; then
  deny "git reset --hard: $CMD"
fi

# --- git push --force / -f ---
if printf '%s' "$CMD" | grep -qE 'git\s+push\s+(-[a-zA-Z]*f[a-zA-Z]*\s+|--force)'; then
  deny "git push --force: $CMD"
fi

# --- git clean -fd / -fdx / -fdq ---
# Флаги: -fd, -fdx, -fdq, -df, -dfx — ищем git clean + флаг с f и d
if printf '%s' "$CMD" | grep -qE 'git\s+clean\s+-[a-zA-Z]*f[a-zA-Z]*d[a-zA-Z]*|git\s+clean\s+-[a-zA-Z]*d[a-zA-Z]*f[a-zA-Z]*'; then
  deny "git clean -fd: $CMD"
fi

exit 0
