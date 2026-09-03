# SPEC-docker-sandbox — станок в Docker (целевая архитектура)

Статус: **ЗАПЛАНИРОВАНО, не реализовано**. Обсуждено с оператором 2026-09-02.
Цель: заменить whitelist-писочницу (`scripts/run.sh` + `hooks/bash-gate.sh`)
на единую границу — контейнер. Модель получает полный bash, но внутри контейнера.

## Почему

- Писочница — колхоз: закрытый whitelist, каждая новая потребность = новая
  подкоманда + правка гейта.
- Docker даёт модели свободу (эксперименты, non-TTY-рендер, python, grep/sed)
  без расширения поверхности атаки: граница — сам контейнер.
- Бонус: одноразовый контейнер (`--rm`) снимает необходимость `git reset --hard`
  и лечит проблему «лаунчер не закоммитил артефакты» (найдено в тикете 030:
  дерево осталось грязным, артефакты спасены операторским коммитом 0048618).

## Архитектура

```
launcher/stanok.py (хост)
  └─ docker run --rm \
       -v $REPO_ROOT:/work -w /work \
       -e ANTHROPIC_BASE_URL=http://192.168.8.131:8080 \
       -e ANTHROPIC_AUTH_TOKEN=local-dummy -e ANTHROPIC_API_KEY="" \
       -e ANTHROPIC_MODEL=$STANOK_MODEL \
       stanok-sandbox:latest \
       claude --settings .claude/settings.stanok.json ...
```

- Образ `stanok-sandbox:latest`: `node:22` + `claude-code` (npm) + `python3` + `jq`.
- Сеть: дефолтный bridge — контейнеру нужен доступ к llama-server
  (192.168.8.131:8080). Хост-фс недоступна (смонтирован только `stanok/`).
- `--rm` — контейнер не остаётся; после выхода — коммит артефактов на хосте.

## Что меняется

1. **Dockerfile** (корень станка, ~10 строк): node:22 → npm i -g @anthropic-ai/claude-code
   → apt: python3, jq.
2. **launcher/stanok.py**: spawn `claude` → spawn `docker run ... claude`
   (~20 строк). Env-константы — те же (STANOK_SERVER_URL и пр.).
3. **`.claude/settings.stanok.json`**: `"allow": [..., "Bash"]` — без кастомных
   bash-хуков; `bash-gate.sh` и `scripts/run.sh` **удаляются**.
4. **`stanok/CLAUDE.md`**: п.2 — «Bash разрешён (контейнер)»; писочница — выкинуть.
5. **Остаётся**: `hooks/verifier.sh` (улучшенный FAIL-блок — ТЗ от 030),
   path-guard, test-lock, malware-scan, agent-gate — все как есть.

## Риск-профиль (честно)

- Модель в контейнере видит только `stanok/` — хост-фс, `~`, `.git` хоста недоступны.
- Сеть: LAN (llama-server + прокси 8118). Риск «вытащит секрет наружу» ≈ 0
  (локальная модель, LAN-машина).
- Docker-дамон = привилегия хоста (docker.sock) — риск уже существует, не новый.
- Первый `docker build` ~2 мин, далее кэш.

## Метрика успеха

- Тикет уровня 030 (4 модуля + тесты): ≤ 40 мин, без слепых ретраев.
- Модель сама гоняет `node --test` в сессии и чинит до зелёного.

## Ограничивающие факты (не лечит docker)

- Зависание llama-server (15 мин в 030) — нужен watchdog-kill, отдельная задача.
- Качество Q3-модели (97 ходов на тривиал) — вопрос модели, не sandbox'а.
