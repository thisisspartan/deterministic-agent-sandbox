# PROBLEM: thinking overhead в агентном цикле станка

Статус: ПАТЧИ НАКАТАНЫ, ВАЛИДНЫЙ A/B ВЫПОЛНЕН (ab006-real, 26.08). Дата: 2026-08-26.

## РЕЗУЛЬТАТ валидного A/B: ab006-real (26.08, реальная работа, thinking off)

### Метод
- Дерево откатано на `3070aca` (pre-fix: глиф '█' U+2588, TDD-красная фаза возможна).
- Прогон `ab006-real` тикета TASK-STANOK-CC-006 на патченном CLI (маркер think_off
  в tool-execution ходах, патчи prompt.ts + messages.ts).
- Станок сделал РЕАЛЬНУЮ работу (не NOOP): tester-субагент обновил тест (красная),
  coder заменил глиф в src (зелёная), docs, reviewer — CLEAN-FIRST. rc=0, verifier PASS.
- Фикс закоммичен: `c71dfaf` (дерево снова в фиксированном состоянии).

### Итог: thinking убран (0 токенов), НО elapsed ХУЖЕ базы — thinking не был узким местом
| Метрика | База fix-006 (thinking on) | ab006-real (thinking off) | Вердикт |
|---|---|---|---|
| elapsed | 1131s | **1583s** | ХУЖЕ на 452s |
| thinking (output_tokens_details) | 29070 ток. | **0 ток.** | ✅ патч работает |
| ходы (main, num_turns) | 25 | 13 | — |
| tool_uses (main) | 25 | ~32 (Read 11, Grep 10, Edit 6, Glob 3, Agent 2) | — |
| output_tokens (main, ResultMessage) | — | 9359 (0 thinking) | — |
| subagents | tester+reviewer | tester + reviewer (обязательные) | — |
| verifier / review | PASS / CLEAN | PASS / CLEAN-FIRST | ✅ |
| rc | 0 | 0 | ✅ |

### Разбор 1583s по control.log (таймстемпы assistant-сообщений)
- Ходы main-агента: 13; длительности между ходами: 63s (первый, planning+3 Read),
  102s (ожидание tester), 102s, 77s, 234s (ожидание reviewer), 122s, 21s, 23s,
  117s, 21s, 292s (финальный отчёт), 0s.
- **Субагенты — доминирующий расход**: tester ~102s (завершён 12:34:47),
  reviewer ~14min (запущен ~12:34:47, завершён 12:48:58).
  Ожидание субагентов ≈ 15.5min из 26.4min elapsed.
- Main-ходы без субагентов: 63+102+77+21+23+117+21+292 ≈ 716s на 8 ходов
  (средний ~90s/ход; контекст до 28k токенов — prefill + decode).
- **Вывод: узкое место — НЕ thinking.** При thinking=0 прогон дольше базы.
  Кандидаты на реальный overhead (по убыванию):
  1. Субагенты (tester/reviewer) — ~15.5min, обязательные по CLAUDE.md станка;
     в базе 1131s они тоже были, но их доля не измерялась.
  2. Медленные main-ходы (63–292s) — prefill растущего контекста (до 28k)
     + decode длинных ответов (финальный отчёт 292s).
  3. «Прочее» (старт/хуки/хвост) — 173s в базе, не разобрано (шаг 3 плана).

### Следующее
- [ ] Сравнение с базой ПО ХОДАМ (control.log fix-006 vs ab006-real): где именно
      база была быстрее — в субагентах или в main-ходах.
- [ ] Шаг 3 плана: разбор 173s «прочего».
- [ ] Решить: нужны ли tester/reviewer-субагенты на каждом тикете (~15min из 26min).
      Если нет — больший выигрыш, чем любое thinking-оптимизирование.
- [ ] Патчи НЕ закоммичены в /home/hermes/git/claude-code-2.1.88 (git status: M).

## РЕЗУЛЬТАТ контрольного прогона fix006-patched (26.08, патчи 1+2 активны)

### Итог: thinking убран, но elapsed НЕ упал — thinking не был единственным узким местом

| Метрика | База (fix-006, 1131s) | fix006-patched | Вердикт |
|---|---|---|---|
| elapsed | 1131s | **1227s** | ХУЖЕ (но см. ниже — прогон NOOP) |
| thinking (сумма по ходам) | 29070 ток. (52% out) | **0 ток.** (output_tokens_details.thinking_tokens=0) | ✅ ПАТЧ РАБОТАЕТ |
| ходы с thinking | 19/25 | **0/47** (все ходы tool-execution = thinking 0) | ✅ |
| tool_uses | 25 | 37 | — |
| verifier / review | PASS / CLEAN | **PASS / CLEAN** | ✅ |
| rc | 0 | 0 | ✅ |

**КРИТИЧЕСКОЕ: прогон NOOP.** `summary.json: noop=true`. Станок обнаружил, что
целевое состояние тикета (глиф '▓' U+2593) УЖЕ присутствовало в дереве на старте
(предыдущий прогон применил и закоммитил фикс). Изменений не внесено — менять
было нечего. TDD-красная фаза невозможна по построению. Reviewer: CLEAN.
**Следовательно, 1227s — НЕ валидное сравнение с базой 1131s**: база делала реальную
работу (TDD red→green), этот прогон — только верификация уже выполненного.
Сравнение elapsed между ними некорректно.

### Что подтверждено прогоном
- **Патч 2 (messages.ts) РАБОТАЕТ**: все 47 ходов tool-execution — thinking=0.
  Маркер `` в tool_result-сообщениях реально гасит thinking на сервере.
- **Сервер подтверждает**: eval time 2.8–3.7s / 154–186 токенов, 49–54 tok/s,
  prompt eval 0.78–0.83s. Никаких thinking-фаз по 140s. MTP жив.
- **Thinking-токены = 0** (ResultMessage output_tokens_details.thinking_tokens=0).

### Вывод по гипотезе «thinking не при чём»
Гипотеза оператора ЧАСТИЧНО подтверждена: thinking действительно убран (0 токенов),
НО это не дало ожидаемого сокращения elapsed, потому что:
1. Прогон NOOP — нет реальной работы, сравнение невалидно.
2. Даже в базе thinking был 52% output-токенов, но LLM-инференс — 85% времени.
   Остальные 15% (173s) — старт/хуки/хвост (шаг 3 плана, не разобран).
3. **Для валидного A/B нужен тикет с РЕАЛЬНОЙ работой** (не noop), прогнанный
   ДО и ПОСЛЕ патча на одинаковом дереве.

### Следующее (нужен оператор)
- [ ] Валидный A/B: новый тикет с реальной работой, прогон на чистом дереве
      (база без патча уже не воспроизвести — патч активен; либо откатить патч
      для контрольного прогона, либо принять текущий прогон как верхнюю границу).
- [ ] Шаг 3 плана: разбор 173s «прочего» (старт/хуки/хвост) — теперь это
      основной кандидат на оставшийся overhead.
- [ ] Патчи НЕ закоммичены в /home/hermes/git/claude-code-2.1.88 (git status: M).

## Замеры (прогон fix-006, 1131s)

| Что | Время | Доля |
|---|---|---|
| LLM-инференс (25 ходов) | 956s | 85% |
| Инструменты (25 вызовов) | 1s | ~0% |
| Прочее (старт/хуки/хвост) | 173s | 15% |

- Thinking = 29070 токенов за 19 ходов (~1530/ход), 52% всех сгенерированных.
- Средний ход 38s; провалы 140/112/110/100s — длинные thinking-фазы.
- cache_read_input_tokens = 608156 — контекст раздут накопленным thinking.

## Метрики llama-server (/tmp/llama-server.log)

- MTP **уже включён** (draft-mtp): acceptance 0.83–0.98, mean len 2.7–4.3,
  acc per pos (0.92, 0.62, 0.44, 0.34). Decode 28–52 tok/s, prefill 370–840 tok/s.
  **Делать ничего не нужно.**
- Prompt size растёт 261 → 2191 токенов по ходу прогона (накопление).
- GPU: RTX 5060 Ti 16GB.

## Root cause (с цитатами)

1. **Claude Code шлёт thinking на каждый ход.** `source/src/services/api/claude.ts:1596-1630`:
   `hasThinking = thinkingConfig.type !== 'disabled' && !CLAUDE_CODE_DISABLE_THINKING`;
   по умолчанию `thinkingConfig = {type:'adaptive'}` (`QueryEngine.ts:278-282`,
   `utils/thinking.ts:146-162`). Пер-turn toggle в цикле НЕТ — thinking уходит
   и на ходах исполнения тулов.
2. **Thinking-блоки сохраняются в истории и пересылаются каждый ход.**
   `claude.ts:654-668` (assistant content map — thinking-блоки проходят как есть),
   `query.ts:151-163` (правило 3: thinking-блоки обязаны сохраняться на всю
   assistant trajectory). Это и есть накопление контекста.
3. **Шаблон чата провоцирует thinking перед каждым tool call.**
   `/data/models/chat_template.jinja` (qwen3.8-froggeric-v22.1): строка 166/168 —
   инструкция «If you choose to call a function ONLY reply ... <tool_call>...»
   + «You can use the  block to plan your next tool call». При включённом
   thinking модель гарантированно генерит thinking-блок перед каждым вызовом.
4. **`reasoning_effort` — только софт-подсказка.** Шаблон строки 18-30, 81-88:
   мапится в текст инструкции («think carefully...»), жёсткого лимита нет.
   Claude Code в body `reasoning_effort` не кладёт (только `thinking:{type}`),
   так что управление идёт через `--chat-template-kwargs` на сервере.
5. **`preserve_thinking` по умолчанию true** (шаблон строки 8-14) — thinking
   рендерится в истории каждого хода.

## Проверенные факты (2026-08-26, сессия супервайзера — командами, не памятью)

### Сервер (cmdline из /proc/35501/cmdline, ssh llm@192.168.8.131)
`llama-server -m Qwen3.8-27B-UD-Q3_K_XL_19.gguf --alias Qwen3.8-27B-MTP -ngl 99
-c 106000 --parallel 1 --spec-type draft-mtp --spec-draft-n-max 4 --spec-draft-p-min 0.8
--reasoning on --no-reasoning-preserve --jinja
--chat-template-file /data/models/chat_template.jinja
--chat-template-kwargs {"reasoning_effort":"xhigh","preserve_thinking":false,"max_tool_response_chars":16000}
--metrics --host 0.0.0.0 --port 8080 -lv 4`
(остальные: threads 8, fa on, cache q4_0, ctx-checkpoints 16, cache-reuse 64,
temp 0.5, top-p 0.95, top-k 40, min-p 0.01, repeat-penalty 1.01/last-n 512).
Логи: `/tmp/llama-server.log` (tee, -lv 4). **ВНИМАНИЕ: трафик этой сессии
супервайзера тоже идёт через этот сервер — логи включают и нашу работу;
на ssh/логах не зацикливаться.**

### A/B: сервер ИГНОРИРУЕТ поле `thinking` в body (curl /v1/messages)
| body | thinking в ответе |
|---|---|
| поля нет | ЕСТЬ (151 char на тривиальном промпте) |
| `{type:'enabled',budget_tokens:2048}` | ЕСТЬ (147) |
| `{type:'disabled'}` | ЕСТЬ (162) |

Следствия:
- `CLAUDE_CODE_DISABLE_THINKING` и `CLAUDE_CODE_DISABLE_ADAPTIVE_THINKING`
  на этот сервер **НЕ влияют** (меняют только body-поле).
- **План шаг 2, варианты A и B — МЁРТВЫ** (оба действуют через body-поле).
- Единственный клиентский рычаг — маркер `<|think_off|>` в промпте.
- Серверные рычаги — рестарт с `--reasoning off` / смена kwargs (оператор: не трогаем).

### A/B: маркер `<|think_off|>` РАБОТАЕТ (curl)
| промпт | elapsed | thinking | text |
|---|---|---|---|
| с `<|think_off|>` | 33.7s | 0 | 4599 chars (полный ответ, 1733 ток.) |
| без | 48.8s | 6190 chars | 0 (бюджет 2000 ток. съеден thinking) |

### Расхождение «оператор vs реальность» (запись исправлена)
- Оператор считает, что сессия запущена с `CLAUDE_CODE_DISABLE_THINKING=1`.
- Реальность: `CLAUDE_CODE_DISABLE_THINKING` **НЕ установлен** ни где
  (env сессии, rc-файлы, P0-launch.sh). Установлен `CLAUDE_CODE_DISABLE_ADAPTIVE_THINKING=1`
  (P0-launch.sh:72) → в body уходит `{type:'enabled', budget}`
  (claude.ts:1596-1630; modelSupportsThinking=true для Qwen3.8-27B-MTP
  через firstParty-ветку thinking.ts:105-106).
- Функционально нерелевантно (см. A/B: сервер игнорирует поле), но запись в спеке
  была неверной — исправлено.

### Патч /home/hermes/git/claude-code-2.1.88 — проверен, АКТИВЕН, НО НЕ В ПУТИ
- `source/src/services/compact/compact.ts` +1 строка: `<|think_off|>` в systemPrompt
  `streamCompactSummary` (thinkingConfig там уже `{type:'disabled'}` — патч дублирует
  выключение на уровне шаблона).
- `cli.js` — тот же патч в minified-форме (1 строка). **НЕ закоммичен** (git status: M).
- `vendor/ripgrep/x64-linux/rg` — бинарник изменился (побочный эффект, глянуть
  при следующем коммите).
- **Патченный CLI реально в работе**: `/home/hermes/.npm-global/bin/claude` →
  `node_modules/@anthropic-ai/claude-code` → symlink на `/home/hermes/git/claude-code-2.1.88`;
  маркер think_off в cli.js найден. Probe (stanok-sdk-probe.py) спавнит CLI через
  SubprocessCLITransport, CLAUDE_BIN по умолчанию = тот же бинарник,
  STANOK_CLAUDE_BIN не задан → станок едет на патченном билде.

### ТРАССРОВКА КОМПАКТА: патч НЕ В ПУТИ (проверено по source, 26.08)
- `compactConversation` (compact.ts:435-458): флаг `tengu_compact_cache_prefix`
  читается с default **true** (3P default, comment 431-434).
- `streamCompactSummary` (compact.ts:1136-1200): если флаг true → **ПУТЬ 1**
  `runForkedAgent({promptMessages:[summaryRequest], cacheSafeParams, ...})`
  (compact.ts:1188-1200) — **systemPrompt НЕ передаётся**; берётся из
  `cacheSafeParams.systemPrompt` = system prompt ГЛАВНОГО цикла
  (forkedAgent.ts:510-516, 135: `createCacheSafeParams` копирует
  `context.systemPrompt`). Путь 1 завершает функцию (return результата).
- **ПУТЬ 2** (fallback, только если путь 1 упал): `queryModelWithStreaming` c
  `systemPrompt: asSystemPrompt([...,'<|think_off|>'])` — **ТОЛЬКО ТАМ патч**
  (compact.ts:1301-1307).
- **ВЕРДИКТ: патч физически не исполняется** (флаг true → путь 1).
  Compact-запрос идёт с thinking (xhigh) и без маркера.
- **A/B подтверждает, что маркер в SYSTEM РАБОТАЕТ** (см. ниже) — значит
  достаточный патч: добавить `<|think_off|>` в system prompt ПУТИ 1
  (точка: compact.ts:1188-1200, runForkedAgent call — добавить/переопределить
  systemPrompt; либо в createCacheSafeParams для compact).

### A/B/C: маркер в SYSTEM vs USER vs нет (curl /v1/messages, 26.08)
| вариант | elapsed | thinking | text |
|---|---|---|---|
| A: маркер в SYSTEM | 38.4s | 0 | 5559 chars (2000 ток.) |
| B: маркер в USER | 30.9s | 0 | 4402 chars (1686 ток.) |
| C: без маркера | 52.9s | 7006 chars | 0 (бюджет съеден) |

Маркер в system prompt работает (шаблон строки 146-149: system-контент
сканируется на маркеры, маркер вырезается, ns_state.thinking=false).

### Шаблон /data/models/chat_template.jinja — обработка маркеров (ssh grep)
- Строки 38-41: user/system/developer string-контент: `<|think_off|>` →
  `ns_state.thinking=false`, `<|think_on|>` → true.
- Строки 62-65: то же для list-контента (item text).
- Строки 143-149: system-контент сканируется на маркеры, маркеры вырезаются
  из текста (split/join), thinking-флаг переключается.
- Строки 202-208: аналогично для всех сообщений при финальном рендере.

## Что уже сделано (НЕ трогать)

- **Сервер перезапущен** с `--reasoning on --no-reasoning-preserve` +
  `--chat-template-kwargs '{"reasoning_effort":"xhigh","preserve_thinking":false,
  "max_tool_response_chars":16000}'` — **всё активно** (проверено cmdline /proc).
- **Сорсы Claude Code в `/home/hermes/git/claude-code-2.1.88` патчены**
  (thinking off для компакшена через `<|think_off|>`); патченный билд реально
  в работе (symlink npm bin → дерево, см. «Проверенные факты»). Не закоммичен.
- `reasoning_effort=xhigh` — не трогаем.
- `CLAUDE_CODE_DISABLE_ADAPTIVE_THINKING=1` (P0-launch.sh:72) — не трогаем.
  (`CLAUDE_CODE_DISABLE_THINKING` НЕ установлен — расхождение с устной записью
  оператора, см. «Проверенные факты»; на этом сервере оба нерелевантны.)

## План (оставшиеся шаги)

### Шаг 1. Замер эффекта уже активных флагов
Прогнать контрольный тикет (например, повтор fix-006 или новый маленький)
с текущими kwargs. Сравнить с fix-006: elapsed, thinking-токены, prompt size.
Ожидание: `preserve_thinking=false` уберёт накопление (prompt 2191 → ~500),
`max_tool_response_chars=16000` урежет большие Read-выводы.
Условия замера (уточнено 26.08): thinking **ВСЕГДА ВКЛЮЧЁН** (xhigh) — клиентские
env не влияют (A/B); маркер в агентном цикле отсутствует (только в compact).
Дешёвые curl A/B (thinking-поле, маркер) уже сделаны — см. «Проверенные факты».

### Шаг 2. Per-turn thinking toggle (основной кандидат)
Цель: thinking только на планировании (первый ход) и после ошибок,
без thinking на ходах исполнения тулов.

- ~~**A. Патч hasThinking** (`claude.ts:1596`)~~ — **МЁРТВЫЙ**: действует через
  body-поле `thinking`, которое сервер игнорирует (A/B выше).
- ~~**B. SDK control `set_max_thinking_tokens`** (`print.ts:2945-2956`)~~ —
  **МЁРТВЫЙ**: то же body-поле.
- **C. Маркеры шаблона** `<|think_off|>`/`<|think_on|>` (шаблон строки 38-51) —
  **ЕДИНСТВЕННЫЙ ЖИВОЙ клиентский рычаг**, проверен A/B (thinking=0).
  Точка инъекции TBD:
  - пер-turn: в собираемые tool_result/user-сообщения (патч в точке сборки
    сообщения) — thinking off только на ходах исполнения тулов;
  - глобально в system prompt — thinking off на весь прогон (грубее, но проще;
    для первого чистого замера скорости может suffice).

Качество проверять по `verifier PASS` + `review_verdict CLEAN` на контрольном
тикете, сравнивать elapsed.

### Шаг 3. Разбор «прочего» 173s (15%)
Старт (SDK init/warmup), хуки, хвост. Замерить по control.log, потом решать.

### Шаг 4. Патч compact ПУТЬ 1 (runForkedAgent) — **ВЫПОЛНЕН (26.08, вариант C)**
Реализовано проще, чем A/B: маркер `<|think_off|>` уже был в `NO_TOOLS_PREAMBLE`
(prompt.ts:19, патч от 25.08), но БЕЗ `\n` после — шаблон сканирует маркер как
prefix строки (`in` + trim), и `<|think_off|>CRITICAL:...` не срабатывал.
Добавлен `\n` после маркера:
- `source/src/services/compact/prompt.ts`: `NO_TOOLS_PREAMBLE` — `<|think_off|>\n` →
  `<|think_off|>\n\n` (маркер теперь standalone на первой строке).
- `cli.js`: 2 вхождения (oWK = getPartialCompactPrompt, aWK = getCompactPrompt) —
  `"<|think_off|>\nCRITICAL:"` → `"<|think_off|>\n\nCRITICAL:"`. `node --check` rc=0.
Патч покрывает ОБА пути (ПУТЬ 1 runForkedAgent и ПУТЬ 2 streaming fallback),
т.к. prompt собирается в getCompactPrompt/getPartialCompactPrompt до выбора пути.
Ожидаемый эффект: компакшн 75k контекста 15min → ~40-60s (prefill 30-45s +
decode 300-400 ток. саммари без reasoning).
**Валидация:** нужен прогон с компакшном (сессия >75k токенов) — замер
thinking=0 в compact-запросе и длительности.

### Шаг 5. Патч агентного цикла: thinking off на ходах исполнения тулов
**Точка:** `normalizeMessagesForAPI` (`source/src/utils/messages.ts:1989`) —
единое место, где ВСЕ user-сообщения (включая tool_result) проходят перед
отправкой в API. Там уже есть прецедент инъекции sibling text-блока
(строки 2159-2185, `TOOL_REFERENCE_TURN_BOUNDARY`).

**Логика:**
- Если последнее user-сообщение содержит tool_result **без** `is_error` →
  добавить sibling text-блок `<|think_off|>`
- Если tool_result **с** `is_error` → НЕ добавлять (thinking нужен после ошибок)
- Первый ход (нет tool_result) → thinking включён (планирование)

**Idempotency:** патч вызывается на каждом API-запросе, поэтому нужно проверять,
не было ли уже добавлено (как в `TOOL_REFERENCE_TURN_BOUNDARY` — `startsWith`
match).

**Что сделать:**
1. Написать патч в `messages.ts` (точка: после строки 2185, перед merge)
2. Применить к `cli.js` (minified-форма)
3. Контрольный прогон fix-006 → сравнение с базой 1131s

## Запрещено в этой сессии (напоминание)
Ничего не менять без отмашки оператора. Гейт `git -C stanok status --porcelain`
перед каждым launch.sh.
