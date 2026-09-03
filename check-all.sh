#!/usr/bin/env bash
set -u
set -o pipefail

ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"
STANOK_DIR="$ROOT_DIR/stanok"

# Цвета для терминала
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

ERRORS=0
WARNINGS=0

pass() { echo -e "  [ ${GREEN}PASS${NC} ] $1"; }
fail() { echo -e "  [ ${RED}FAIL${NC} ] $1"; ((ERRORS++)); }
warn() { echo -e "  [ ${YELLOW}WARN${NC} ] $1"; ((WARNINGS++)); }
info() { echo -e "${BLUE}=== $1 ===${NC}"; }

echo ""
info "СТАРТ СКВОЗНОГО АУДИТА СИСТЕМЫ"
echo ""

# ---------------------------------------------------------------------------
# 1. Проверка чистоты Git в субмодуле stanok (Защита от rc=22)
# ---------------------------------------------------------------------------
info "1. Проверка Git-дерева в stanok/ (Защита от rc=22)"
if [ ! -d "$STANOK_DIR" ]; then
    fail "Директория станка не найдена: $STANOK_DIR"
else
    DIRTY_FILES="$(git -C "$STANOK_DIR" status --porcelain 2>/dev/null || true)"
    if [ -z "$DIRTY_FILES" ]; then
        pass "Рабочее дерево stanok/ абсолютно чистое (станок не упадет с rc=22)"
    else
        fail "Рабочее дерево stanok/ ГРЯЗНОЕ! Станок откажется запускаться."
        echo "$DIRTY_FILES" | while read -r line; do
            echo -e "       ${RED}→ $line${NC}"
        done
        echo -e "     ${YELLOW}Решение: закоммить изменения через: git -C stanok add -A && git -C stanok commit -m 'chore'${NC}"
    fi
fi
echo ""

# ---------------------------------------------------------------------------
# 2. Проверка ролевой изоляции (Role Leak Guard, rc=24)
# ---------------------------------------------------------------------------
info "2. Проверка ролевой изоляции (Role-Leak Guard)"
if [ -f "$ROOT_DIR/CLAUDE.md" ]; then
    fail "Найден $ROOT_DIR/CLAUDE.md в корне! Это вызовет ролевой утечки (rc=24)."
    echo -e "     ${YELLOW}Решение: переименуй или удали корневой CLAUDE.md. Роль супервайзера должна быть в CLAUDE.supervisor.md${NC}"
else
    pass "Корневой CLAUDE.md отсутствует — ролевой утечки не будет"
fi

if [ -f "$ROOT_DIR/CLAUDE.supervisor.md" ]; then
    pass "Файл роли L1-супервайзера найден: CLAUDE.supervisor.md"
else
    fail "Файл CLAUDE.supervisor.md не найден в корне проекта!"
fi
echo ""

# ---------------------------------------------------------------------------
# 3. Проверка прав на исполнение скриптов (chmod +x)
# ---------------------------------------------------------------------------
info "3. Проверка прав на исполнение (+x)"
check_exec() {
    local file="$1"
    if [ ! -f "$file" ]; then
        fail "Файл отсутствует: $file"
    elif [ ! -x "$file" ]; then
        fail "Файл НЕ исполняемый (нет +x): $file"
        echo -e "     ${YELLOW}Решение: chmod +x $file${NC}"
    else
        pass "Права +x в порядке: $(basename "$file")"
    fi
}

check_exec "$ROOT_DIR/P0-launch.sh"
check_exec "$STANOK_DIR/launch.sh"
check_exec "$STANOK_DIR/sandbox-run.sh"
check_exec "$STANOK_DIR/launcher/stanok.py"
echo ""

# ---------------------------------------------------------------------------
# 4. Проверка конфига .claude/settings.stanok.json (Чистота от старых хуков)
# ---------------------------------------------------------------------------
info "4. Проверка конфигурации станка (.claude/settings.stanok.json)"
SETTINGS_FILE="$STANOK_DIR/.claude/settings.stanok.json"

if [ ! -f "$SETTINGS_FILE" ]; then
    fail "Файл настроек не найден: $SETTINGS_FILE"
else
    python3 -c "
import json, sys
try:
    with open('$SETTINGS_FILE') as f:
        d = json.load(f)
    has_hooks = 'hooks' in d and bool(d['hooks'])
    bash_allowed = 'Bash' in d.get('permissions', {}).get('allow', [])

    if has_hooks:
        print('FAIL_HOOKS')
    elif not bash_allowed:
        print('FAIL_BASH')
    else:
        print('OK')
except Exception as e:
    print('ERR:' + str(e))
" | while read -r res; do
        case "$res" in
            "OK")
                pass "Конфиг валиден: секция 'hooks' удалена, 'Bash' в списке разрешенных"
                ;;
            "FAIL_HOOKS")
                fail "В конфиге всё ещё присутствует секция 'hooks'! Удали её, хуки тормозят станок."
                ;;
            "FAIL_BASH")
                fail "В permissions.allow отсутствует 'Bash'! Добавь 'Bash' в allow."
                ;;
            ERR:*)
                fail "Синтаксическая ошибка в JSON конфига: ${res#ERR:}"
                ;;
        esac
    done
fi
echo ""

# ---------------------------------------------------------------------------
# 5. Проверка чистоты stanok/CLAUDE.md от призраков хуков
# ---------------------------------------------------------------------------
info "5. Проверка инструкций станка (stanok/CLAUDE.md)"
STANOK_CLAUDE="$STANOK_DIR/CLAUDE.md"

if [ ! -f "$STANOK_CLAUDE" ]; then
    fail "Файл $STANOK_CLAUDE не найден!"
else
    PHANTOMS="$(grep -E "(malware-scan|test-lock|pending-\*\.flag|SECURITY-PENDING)" "$STANOK_CLAUDE" || true)"
    if [ -n "$PHANTOMS" ]; then
        warn "В stanok/CLAUDE.md найдены упоминания старых хуков (модель может путаться):"
        echo "$PHANTOMS" | head -3 | while read -r p; do
            echo -e "       ${YELLOW}→ $p${NC}"
        done
    else
        pass "stanok/CLAUDE.md чист от призраков старых хуков"
    fi
fi
echo ""

# ---------------------------------------------------------------------------
# 6. Проверка работоспособности песочницы bwrap
# ---------------------------------------------------------------------------
info "6. Проверка песочницы Bubblewrap (bwrap)"
if ! command -v bwrap &>/dev/null; then
    fail "Утилита bwrap не установлена в системе! (sudo apt install bubblewrap)"
else
    # Тестовый прогон: пробуем сделать запись в /etc внутри bwrap
    BWRAP_TEST="$("$STANOK_DIR/sandbox-run.sh" bash -c "rm -rf /etc 2>&1 || true" 2>/dev/null || true)"
    if [[ "$BWRAP_TEST" == *"Read-only file system"* ]]; then
        pass "Песочница bwrap работает идеально: корень ОС намертво защищен (Read-only)"
    else
        warn "Песочница bwrap запустилась, но ответ защиты нестандартный: $BWRAP_TEST"
    fi
fi
echo ""

# ---------------------------------------------------------------------------
# 7. Проверка доступности llama-server и его параметров
# ---------------------------------------------------------------------------
info "7. Проверка инференс-сервера (llama-server)"
SERVER_URL="http://192.168.8.131:8080"
PROPS="$(curl -s --noproxy '*' --max-time 3 "$SERVER_URL/props" 2>/dev/null || true)"

if [ -n "$PROPS" ]; then
    MODEL_ALIAS="$(python3 -c "import json; print(json.loads('''$PROPS''').get('model_alias', '?'))" 2>/dev/null || echo "?")"
    pass "llama-server доступен по адресу $SERVER_URL (Модель: $MODEL_ALIAS)"

    # Проверяем, с какими параметрами запущен сервер через ps (если сервер на этой же машине)
    CMDLINE="$(ps aux | grep llama-server | grep -v grep || true)"
    if [ -n "$CMDLINE" ]; then
        if [[ "$CMDLINE" == *'"preserve_thinking":true'* ]]; then
            pass "Сервер запущен с 'preserve_thinking': true (KV-кэш защищен)"
        else
            warn "В параметрах llama-server не найдено 'preserve_thinking': true!"
        fi

        if [[ "$CMDLINE" == *'"reasoning_effort":"medium"'* ]]; then
            pass "Сервер запущен с 'reasoning_effort': 'medium' (Системный промпт заморожен)"
        else
            warn "В параметрах llama-server не найдено 'reasoning_effort': 'medium'!"
        fi
    fi
else
    fail "llama-server НЕДОСТУПЕН по адресу $SERVER_URL!"
    echo -e "     ${YELLOW}Убедись, что сервер запущен и слушает порт 8080.${NC}"
fi
echo ""

# ---------------------------------------------------------------------------
# Итог
# ---------------------------------------------------------------------------
info "ИТОГОВЫЙ РЕЗУЛЬТАТ АУДИТА"
if [ "$ERRORS" -eq 0 ]; then
    echo -e "${GREEN}✔ ВСЕ КРИТИЧЕСКИЕ ПРОВЕРКИ ПРОЙДЕНЫ УСПЕШНО! (Ошибок: 0, Предупреждений: $WARNINGS)${NC}"
    echo -e "Конвейер полностью готов к автономному бою. Запускай: ${BLUE}./P0-launch.sh${NC}"
    exit 0
else
    echo -e "${RED}✖ ОБНАРУЖЕНО КРИТИЧЕСКИХ ОШИБОК: $ERRORS (Предупреждений: $WARNINGS)${NC}"
    echo -e "Устрани ошибки выше перед боевым запуском."
    exit 1
fi
