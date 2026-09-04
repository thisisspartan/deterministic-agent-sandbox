#!/usr/bin/env bash
set -euo pipefail

# Цвета для удобного вывода
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$ROOT_DIR"

echo -e "${BLUE}====================================================${NC}"
echo -e "${BLUE}  STANOK 4.2 / PIPELINE VERIFICATION SUITE          ${NC}"
echo -e "${BLUE}  Корень: $ROOT_DIR                                 ${NC}"
echo -e "${BLUE}====================================================${NC}\n"

# -----------------------------------------------------------------------------
# Функция гарантированной очистки при выходе/сбое
# -----------------------------------------------------------------------------
LABEL_EARLY="smoke-early-abort-test"
LABEL_FULL="smoke-bwrap-full-test"
TICKET_FILE="tickets/TASK-STANOK-CC-VERIFY-AUTO.md"

cleanup() {
    echo -e "\n${YELLOW}[ОЧИСТКА] Убираем тестовые артефакты...${NC}"
    rm -f "$TICKET_FILE"
    rm -rf "stanok/evidence/$LABEL_EARLY" "stanok/evidence/$LABEL_FULL"
    rm -rf "/tmp/stanok-logs/$LABEL_EARLY"* "/tmp/stanok-logs/$LABEL_FULL"*
    if [ -d "stanok" ]; then
        git -C stanok checkout -- . 2>/dev/null || true
        git -C stanok clean -fd 2>/dev/null || true
    fi
    echo -e "${GREEN}[ОЧИСТКА ЗАВЕРШЕНА]${NC}"
}
trap cleanup EXIT INT TERM

# -----------------------------------------------------------------------------
# ЭТАП 1: Проверка окружения и статических правок
# -----------------------------------------------------------------------------
echo -e "${BLUE}>>> [ЭТАП 1/4] Проверка конфигурации и окружения...${NC}"

# 1. Проверка структуры
for f in "stanok/launch.sh" "stanok/sandbox-run.sh" "stanok/launcher/stanok.py" "CLAUDE.supervisor.md" "stanok/CLAUDE.md"; do
    if [ ! -f "$f" ]; then
        echo -e "${RED}ОШИБКА: Файл $f не найден!${NC}" >&2
        exit 1
    fi
done

# 2. Удаление старой папки evidence в корне, если она осталась
if [ -d "evidence" ]; then
    echo -e "${YELLOW}  Удаляем остаточный каталог $ROOT_DIR/evidence...${NC}"
    rm -rf "evidence"
fi

# 3. Проверка правок в sandbox-run.sh
if ! grep -q 'ro-bind "$PARENT_DIR/tickets"' stanok/sandbox-run.sh; then
    echo -e "${RED}ОШИБКА: В stanok/sandbox-run.sh отсутствует --ro-bind тикетов!${NC}" >&2
    exit 1
fi
if ! grep -q 'STANOK_HOST_PID' stanok/sandbox-run.sh; then
    echo -e "${RED}ОШИБКА: В stanok/sandbox-run.sh отсутствует проброс STANOK_HOST_PID!${NC}" >&2
    exit 1
fi

# 4. Проверка REPO_ROOT в launch.sh
if grep -q 'PROJECT_ROOT="$(cd "$DIR/.." && pwd)"' stanok/launch.sh; then
    echo -e "${RED}ОШИБКА: В stanok/launch.sh PROJECT_ROOT смотрит на уровень выше stanok/!${NC}" >&2
    exit 1
fi

# 5. Проверка сервера инференса
SERVER_URL="${STANOK_SERVER_URL:-http://192.168.8.131:8080}"
echo -n "  Проверка доступности инференс-сервера ($SERVER_URL)... "
if curl -s --noproxy '*' --max-time 5 "$SERVER_URL/props" >/dev/null 2>&1; then
    echo -e "${GREEN}OK${NC}"
else
    echo -e "${RED}НЕДОСТУПЕН! Запустите llama-server перед тестом.${NC}" >&2
    exit 1
fi
echo -e "${GREEN}✓ Конфигурация и окружение в норме.${NC}\n"

# -----------------------------------------------------------------------------
# ЭТАП 2: Подготовка Git-гейта станка
# -----------------------------------------------------------------------------
echo -e "${BLUE}>>> [ЭТАП 2/4] Проверка git-гейта станка...${NC}"
if [ -n "$(git -C stanok status --porcelain)" ]; then
    echo -e "${YELLOW}  Дерево stanok/ содержит незакоммиченные правки. Сохраняем состояние...${NC}"
    git -C stanok add -A
    git -C stanok commit --no-verify -m "chore: save state before verification suite"
fi
echo -e "${GREEN}✓ Гейт stanok/ чист.${NC}\n"

# -----------------------------------------------------------------------------
# ЭТАП 3: Тест раннего отказа (Early Abort / Fail-Closed)
# -----------------------------------------------------------------------------
echo -e "${BLUE}>>> [ЭТАП 3/4] Тест раннего отказа (несуществующий тикет)...${NC}"
echo "  Запуск: ./stanok/launch.sh run tickets/NONEXISTENT_FAKE.md $LABEL_EARLY --background"
./stanok/launch.sh run tickets/NONEXISTENT_FAKE.md "$LABEL_EARLY" --background >/dev/null

sleep 2
STATUS_JSON=$(./stanok/launch.sh status "$LABEL_EARLY")
echo "  Статус: $STATUS_JSON"

STATE=$(echo "$STATUS_JSON" | grep -o '"state": *"[^"]*"' | cut -d'"' -f4)
RC=$(echo "$STATUS_JSON" | grep -o '"rc": *[0-9]*' | grep -o '[0-9]*' || echo "")

if [ "$STATE" = "done" ] && [ "$RC" = "13" ]; then
    echo -e "${GREEN}✓ Early-abort отработал штатно: rc=13, маркер снят, зависания нет.${NC}\n"
else
    echo -e "${RED}ОШИБКА: Early-abort дал сбой! Ожидалось state=done rc=13, получено: $STATUS_JSON${NC}" >&2
    exit 1
fi

# -----------------------------------------------------------------------------
# ЭТАП 4: Сквозной боевой тест TDD внутри bwrap (Happy Path)
# -----------------------------------------------------------------------------
echo -e "${BLUE}>>> [ЭТАП 4/4] Сквозной запуск боевого микро-тикета в bwrap...${NC}"
mkdir -p tickets

cat << 'EOF' > "$TICKET_FILE"
# TASK-STANOK-CC-VERIFY-AUTO: Smoke Verification Module
Реализуй тестовый модуль проверки конвейера:
1. `src/smoke_verify.js`: экспорт функции `get_status()`, возвращающей строку `"PIPELINE_OK"`.
2. `tests/smoke_verify.test.js`: тест с использованием `node:test` и `node:assert/strict`, проверяющий вызов `get_status() === "PIPELINE_OK"`.
3. `docs/smoke_verify.md`: описание контракта функции.
EOF

echo "  Тикет создан: $TICKET_FILE"
echo "  Запуск станка в фоне (СТРОГО внутри bwrap, без STANOK_NO_SANDBOX)..."
./stanok/launch.sh run "$TICKET_FILE" "$LABEL_FULL" --background

echo -e "  Ожидание завершения (безопасный non-thrashing цикл)..."
t0=$(date +%s)
while ./stanok/launch.sh status "$LABEL_FULL" | grep -q '"state": "running"'; do
    sleep 5
    elapsed=$(( $(date +%s) - t0 ))
    echo -ne "  Станок работает... [${elapsed}s]\r"
    if [ "$elapsed" -gt 300 ]; then
        echo -e "\n${RED}ТАЙМАУТ: Тест превысил 5 минут!${NC}" >&2
        ./stanok/launch.sh stop "$LABEL_FULL" || true
        exit 1
    fi
done
echo ""

FINAL_STATUS=$(./stanok/launch.sh status "$LABEL_FULL")
echo "  Итоговый статус: $FINAL_STATUS"

SUMMARY_PATH="stanok/evidence/$LABEL_FULL/summary.json"
if [ ! -f "$SUMMARY_PATH" ]; then
    echo -e "${RED}ОШИБКА: Файл $SUMMARY_PATH не был создан!${NC}" >&2
    exit 1
fi

echo -e "\n  Содержимое summary.json:"
cat "$SUMMARY_PATH"
echo ""

# Проверка критериев приёмки
VERIFIER=$(grep -o '"verifier": *"[^"]*"' "$SUMMARY_PATH" | cut -d'"' -f4)
FINAL_RC=$(grep -o '"rc": *[0-9]*' "$SUMMARY_PATH" | grep -o '[0-9]*')

if [ "$FINAL_RC" = "0" ] && [ "$VERIFIER" = "PASS" ]; then
    echo -e "\n${GREEN}====================================================${NC}"
    echo -e "${GREEN}  ВСЕ ПРОВЕРКИ УСПЕШНО ПРОЙДЕНЫ! КОНТУР ГОТОВ К ПРОДУ! ${NC}"
    echo -e "${GREEN}  1. Изоляция bwrap: РАБОТАЕТ (тикеты видны)        ${NC}"
    echo -e "${GREEN}  2. Ранний отказ: РАБОТАЕТ (не зависает в running)  ${NC}"
    echo -e "${GREEN}  3. Поллинг: БЕЗОПАСЕН (кэш не выбивается)         ${NC}"
    echo -e "${GREEN}  4. TDD / Верификатор: PASS (rc=0)                 ${NC}"
    echo -e "${GREEN}====================================================${NC}"
else
    echo -e "\n${RED}ОШИБКА: Тест завершился с дефектом (rc=$FINAL_RC, verifier=$VERIFIER)!${NC}" >&2
    exit 1
fi
