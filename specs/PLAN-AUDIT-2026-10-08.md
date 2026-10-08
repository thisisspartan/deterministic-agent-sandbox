# PLAN-AUDIT-2026-10-08: актуализация по итогам аудита публичного клона

Контекст: аудит делался на клоне публичного репо (сабмодуль `99396ed`). Darkcast на `7a3dda8` (CC-208).
Пункты аудита перепроверены по факту на текущем HEAD. Все правки ниже — **operator-side**
(infra/docs вне машины: `launcher/`, `hooks/`, `.claude/`, `Dockerfile`, docs); это не TASK-STANOK-CC тикеты —
машина пишет только в `src/ tests/ docs/ scripts/run.sh`.

## A. Уже исправлено в darkcast — no action (аудит видел старый коммит)

- `.claude/e2e.sh` — уже на `--follow` (STATUS.md 2026-10-01).
- Корневой `README.md` — актуален: `--background` как флаг не упоминается, PreToolUse-хук не описан.
- Заголовок `scripts/run.sh` — описывает TOML-реестр, однострочного формата нет.
- `STANOK_TEMP` — НЕ мёртвый: читается T-патчем cli.js (CONTEXT.md:202-204), settings.stanok.json = "0.0".
- `STANOK_PROXY` — НЕ мёртвый: P0-launch.sh:84-85 экспортирует из него `http_proxy`/`https_proxy`.
- `CONTEXT.md`, `specs/`, `tickets/`, `opik-traces.py` — в darkcast есть; отсутствуют только в публичном клоне.
- `preflight_image` — вызывается через doctor (hooks/doctor.sh → test_doctor.py), согласовано с CC-106.

## B. Реальные дефекты — чинить (по приоритету)

### B1. `scripts/stacks/*.toml` не под contract lock (целостность вердикта)
- Факт: `_protected_files()` (stanok.py:1079) = `tests/**` + `scripts/run.sh`; `scripts/` — RW-зона машины;
  `run.sh` берёт `test_runner`/`test_glob` из TOML. Машина может переписать `test_runner` → фейковый PASS.
- Исправление: добавить `scripts/stacks/*.toml` в `_protected_files()` — один источник даёт и RO-bind,
  и contract lock (CLAUDE.md уже запрещает машине их редактировать — enforcement просто совпадает с правилом).
- Попутно: stanok.py:600 log-строка «sha256(Dockerfile+run.sh)» устарела — дайджест включает stacks (stanok.py:553-565).
- Тест: новый кейс в tests_harness — изменение stacks-TOML в ране → contract_lock_violation.

### B2. `.claude/commands/e2e.md:19` устарел
- Факт: описывает `--background` + `while ... status ... running` loop; актуально: `--follow` (единственный флаг).
- Исправление: переписать под текущий протокол e2e.sh.

### B3. Комментарии в `Dockerfile` устарели (строки 50, 94, 134)
- Факт: утверждают, что `preflight_image` rc=25 проверяется при запуске; код: CC-106 перенёс в doctor.
- Исправление: переформулировать под doctor-проверку.

### B4. Мёртвое поле `SessionPlan.git_mode`
- Факт: задаётся (stanok.py:102, 1911), читается только тестами.
- Исправление: удалить поле + правки в test_session_plan.py / test_ro_protected_files.py (operator-side, tests_harness — не protected-зона машины).

### B5. Конфликт дефолтных портов
- Факт: llama-server `:8080` (P0-launch.sh:55), Opik `STANOK_OPIK_URL` дефолт `http://localhost:8080` (stanok.py:627).
- Исправление: сменить дефолт Opik на его штатный порт (5173) либо обязательный явный env; минимум — документировать.

## C. Обсудить (дизайн-решения, не «баги»)

### C1. `cmd_wait` возвращает 0 при любом терминальном состоянии (stanok.py:2038-2040)
- Аудит зовёт это багом; по коду это сознательный контракт: docstring + e2e.sh Gate 2 явно полагаются
  («completed-but-failed run returns 0 here and is judged in Gate 2»). Вердикт supervisor читает из summary.json.
- Вариант менять: `--follow` транслирует rc верификатора → фоновая задача падала бы nonzero при DEFECT.
  Цена: ломает e2e.sh Gate 1/Gate 2 семантику и test_wait_follow. Рекомендация: НЕ менять; зафиксировать в README.

### C2. NO-OP-проб считает только Write/Edit (stanok.py:1667)
- Дыра: машина может создать реализацию через Bash (heredoc) на turn 1 → NO-OP-PASS при реально сделанной работе.
- Вариант: сравнение снапшота дерева `src/` до/после рана (или diff по git) как второй сигнал NO-OP.
  Требует spec до реализации.

### C3. Жёсткие пути `/home/hermes/…`
- `CLAUDE.supervisor.md` — абсолютные пути обязательны by design (CC-158); это операторский конфиг, не переносимый код.
- `sync-skeleton.sh` уже поддерживает `DST=` override — ок. `settings.local.json` — локальные allowlist, ок.
- Рекомендация: ничего не менять; при переносе на другого оператора — правка operator-side.

## D. Публичный репозиторий (skeleton-pub) — отдельная линия

- Публичный клон на старом сабмодуле (`99396ed`) и без supervisor-zone файлов (`CONTEXT.md`, `specs/`, `tickets/`, `opik-traces.py`).
- Решение: либо синхронизировать через sync-skeleton (решить, что из supervisor-зоны публикуется),
  либо признать публичный репо «infra-скелетом» и убрать из его документов ссылки на unpublished-файлы.

## Порядок работ

1. B1 (+ тест) — целостность вердикта, высший приоритет.
2. B2, B3 — docs-правки, безопасно.
3. B4 — удаление мёртвого поля.
4. B5 — смена дефолта/документация.
5. C1, C2 — решения после обсуждения; C2 требует spec.
6. D — решение оператора по skeleton-pub.
