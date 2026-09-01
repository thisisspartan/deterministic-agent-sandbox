# PLAN — thinking control (final answer + errors) и компакция/KV

Дата: 2026-09-01. Статус: **ПОДТВЕРЖДЁН оператором (вариант B1 — think_low)**. Не применено.
Решение оператора: B1. B0 и B2 отложены (см. §3).
Источник: живые замеры `/v1/messages` (2026-09-01), шаблон `/data/models/chat_template.jinja.new`
(ssh llm@192.168.8.131, cat), cmdline llama-server (ps), сорцы+bundle claude-code-2.1.88 (git, HEAD 55b28d3).

---

## 0. Кратко (что и почему)

**Баг оператора подтверждён эмпирически.**
- После первого tool-хода думание гаснет ДО конца задачи: клиент вставляет `<|think_off|>`
  в каждый tool_result-батч без ошибки → шаблон предзаполняет пустой `<think>\n\n</think>`
  на следующем ходе → модель СТРУКТУРНО не может думать (в т.ч. на финальном ответе).
- Ошибка НЕ включает думание: на error-tool_result клиент НЕ вставляет маркер → шаблон
  берёт защёлку `ns_state.thinking`, которую ранее сбросил `<|think_off|>` → думание остаётся OFF.
- Старый фикс `<|think_on|>` на ошибках (dec2911) давал бесконечное xhigh-думание (788+ символов
  съедали бюджет) → тот самый loop. Ревёрт (55b28d3) вернул «думание OFF после первого тула».

**Рабочий фикс (замерен):** `<|think_low|>` на tool-ходах даёт КОРОТКОЕ думание
(~100–136 символов) и корректное завершение хода. Оно:
- включает думание после tool use (в т.ч. на финальном ответе) — «включено после того как тул отработал»;
- включает думание после ошибки (ограниченное, без loop);
- не съедает бюджет (в отличие от xhigh-`think_on`).

**Компакция и KV-кэш — уже почти оптимальны**, нужны проверки/устранение расхождения env, а не новые патчи.

---

## 1. Проверенные факты (без допущений)

### 1.1 Проводка
- Бинарь: `/home/hermes/.npm-global/bin/claude` → symlink → `~/git/claude-code-2.1.88/cli.js` (2.1.88, HEAD 55b28d3, дерево чистое).
- Агентные вызовы: `http://192.168.8.131:8080/v1/messages` (llama-server, Anthropic-совместимость).
- cmdline сервера (ssh, ps, 2026-09-01):
  `-c 100000 --parallel 1 --reasoning on --no-reasoning-preserve --jinja
  --chat-template-file /data/models/chat_template.jinja.new
  --chat-template-kwargs {"reasoning_effort":"xhigh","preserve_thinking":false,"max_tool_response_chars":16000}
  --ctx-checkpoints 32 --checkpoint-min-step 1024 --cache-ram 40960
  --spec-type draft-mtp --spec-draft-n-max 5 --spec-draft-p-min 0.7
  --temp 0.45 --cache-type-k q4_0 --cache-type-v q4_0 -lv 4`
- Модель: `Qwen3.8-27B-UD-Q3_K_XL_19.gguf` (qwen35, hybrid/recurrent).

### 1.2 Два уровня управления думанием
- **Клиент** (`source/src/utils/messages.ts:2194-2220`, bundle `bP` в cli.js): в user-сообщение,
  где есть tool_result БЕЗ `is_error` и ещё нет маркера, добавляется sibling text-блок `<|think_off|>`.
  Error-tool_result — БЕЗ маркера. Планирующий ход (нет tool_result) — без маркера.
- **Шаблон** `chat_template.jinja.new` (полностью прочитан):
  - пре-пас по всем system/user сообщениям сканирует маркеры: `think_off`→thinking=false,
    `think_on`→true, `think_xhigh/high`→true+effort=xhigh, `think_low/minimal`→true+effort=low,
    `think_medium`→true+effort=medium. **Побеждает ПОСЛЕДНИЙ маркер.**
  - `reasoning_instructions` в system-блок: xhigh → «think carefully…», low → «keep brief…».
  - маркеры ВЫРЕЗАЮТСЯ из рендера (модель их не видит; prefix стабилен для KV).
  - генерационный префикс `_want_think`:
    - system содержит think_off → пустой `<think>\n\n</think>` (думать нельзя);
    - последний user содержит think_off → пустой думать;
    - последний user содержит think_on/think_low/think_xhigh → открытый `<think>` (думает);
    - последнее сообщение = tool_result (рендерится как `<tool_response>…</tool_response>`) → `_want_think = ns_state.thinking` (**защёлка**);
    - обычный user → думание ON.

### 1.3 Живое поведение (замеры `/v1/messages`, 2026-09-01)
| Сценарий | Думание | Примечание |
|---|---|---|
| plain user | THINK=59 | планирование xhigh |
| tool_result ok без маркера | THINK=86 | защёлка true (свежий контекст) |
| tool_result error без маркера (свежий ctx) | THINK=296 + TOOL_USE | думает |
| tool_result + `<|think_off|>` (текущий клиент) | **НЕТ** | структурное выключение |
| **error ПОСЛЕ предыдущего think_off** | **НЕТ** | **защёлка залипла false → баг оператора** |
| error + `<|think_on|>` | THINK=788 (бюджет выест) | причина loop |
| **error + `<|think_low|>`** | **THINK=136 + чистый текст** | **ограниченный фикс** |
| tool_result + `<|think_low|>` | THINK=100 + текст | дёшево |
| tool_result + `<|think_on|>` | THINK=86 | включено |

### 1.4 Компакция и KV (уже работает)
- Fork-compact (`tengu_compact_cache_prefix` default true → `runForkedAgent`, `compact.ts:1188-1200`)
  шлёт summaryRequest в форке с тем же префиксом → reuse 96.8–99.7% (замеры CONTEXT.md);
  боевой: prompt eval 69 токенов вместо 25878, 651ms.
- Живой сервер (7ч аптайма): **96.4% промпт-токенов из кэша** (13.8M cached vs 515K fresh; /metrics).
- Compact-промпт: `NO_TOOLS_PREAMBLE` начинается с `<|think_off|>` → компакция думает OFF
  (путь 1 — маркер в summaryRequest-user; путь 2 — маркер в system + thinkingConfig disabled).
- Секция 6 без потерь (все сообщения с требованиями), `<analysis>` ограничен и вырезается
  (`formatCompactSummary`), пример-блоки удалены (7248→6038 ток., 212→160s, качество 100%).
- `preserve_thinking:false` → думание не копится в истории → префикс стабилен → KV не раздувается.
- Маркеры вырезаются при рендере → НЕ ломают KV-префикс.

---

## 2. Root cause (коротко)

1. **«Думание OFF до конца задачи»** = клиентский `<|think_off|>` на каждом не-error tool_result.
   Финальный ответ всегда следует за tool_result-батчем → его ход получает пустой `<think>` → думать нельзя.
2. **«Ошибка не включает думание»** = error-tool_result без маркера → шаблон берёт защёлку
   `ns_state.thinking`, сбитую ранними think_off → OFF. (В свежем контексте защёлка true,
   поэтому на ранних ходах прогона ошибки «работали».)
3. **Loop от dec2911** = `<|think_on|>` на ошибке давал xhigh-думание без ограничения →
   65k-char thinking, бюджет выеден, нет text/tool_use → re-prompt loop.

---

## 3. Фикс думания — ВАРИАНТЫ

### Вариант B1 (РЕКОМЕНДОВАН, минимальный патч клиента)
`messages.ts` (и minified-форма в `cli.js`, функция `bP`):

```js
// ТЕКУЩЕЕ:
if (trBlocks.length > 0 &&
    !trBlocks.some(b => b.is_error) &&           // ошибки не получают маркер
    !hasMarker) {
  append { type:'text', text:'<|think_off|>' }
}

// НОВОЕ:
if (trBlocks.length > 0 && !hasMarker) {
  const marker = trBlocks.some(b => b.is_error)
    ? '<|think_low|>'   // ошибка → ограниченное думание (без loop)
    : '<|think_low|>'   // обычный tool-ход → короткое думание (не OFF)
  append { type:'text', text: marker }
}
```
Идемпотентность: расширить `hasMarker`, чтобы ловил `<|think_low|>`/`<|think_medium|>`/`<|think_xhigh|>`
(сейчас только think_off/think_on), иначе маркер может накапливаться.

Эффект (замерен): после tool use думание ~100 симв. (кратко), после ошибки ~136 симв. + корректный
tool_use/текст, планирующий ход остаётся xhigh. `ab006-real` доказал: думание НЕ узкое место
(thinking=0 дал elapsed ХУЖЕ базы на 452s) — добавка ~100 симв/ход на скорость почти не влияет.

### Вариант B0 (максимально простое: xhigh ВЕЗДЕ)
Убрать инъекцию вообще → защёлка остаётся true (начальный xhigh) → думание на ВСЕХ ходах,
включая финальный и ошибки. Самый верный по смыслу «xhigh не должен гаснуть», но каждый
tool-ход думает xhigh (медленнее, возврат к до-THINK-OFF поведению).

### Вариант B2 (если нужен именно XHIGH на финальном ответе)
Клиент не знает, какой tool_result предшествует финалу. Решение — на стороне шаблона:
для tool_result-ходов эмитить `<|im_start|>assistant\n` БЕЗ префикса `<think>` + инструкция
«перед ФИНАЛЬНЫМ ответом обязательно думай (xhigh)». Модель сама выбирает. Рандаптит дёшево,
финал думает xhigh. Риск: несоответствие модели, нужен валидационный прогон.
**Порядок: сначала B1 (доказанный), потом A/B B2, если оператор хочет глубже финальный думать.**

---

## 4. Компакция и KV — что сделать

Компакция и KV уже близки к оптимуму. Остаётся:

1. **Устранить расхождение env компакции:**
   - `~/.claude/settings.stanok.json` (грузится станком через `settings=` в stanok.py): `CLAUDE_CODE_MAX_OUTPUT_TOKENS="20000"`.
   - `~/darkcast/P0-launch.sh`: `CLAUDE_CODE_MAX_OUTPUT_TOKENS="10000"`.
   - CONTEXT.md фиксирует порог 86240 (= MAX_OUTPUT 10000). При 20000 порог станет 76240.
   - С `CLAUDE_AUTOCOMPACT_PCT_OVERRIDE=95`: 20000 → 76240; 10000 → 86240.
   - Задача: выбрать одно значение, зафиксировать в обоих местах, проверить в живом логе строку
     `autocompact: tokens=… threshold=…` (логи /tmp/stanok-logs были очищены — замерить при следующем прогоне).
2. **Проверить, что компакция реально срабатывает** в длинном прогоне (autocompact в логе +
   reuse% + качество summary по аудиту файлы/ошибки/следующий шаг). Сейчас доказ: замеры CONTEXT.md.
3. **KV: флаги менять не нужно.** Маркеры вырезаются при рендере (prefix стабилен),
   fork-compact + ctx-checkpoints 32 + min-step 1024 дают 97–99% reuse. Опционально (сервер,
   решение оператора): поднять `-b 512` для ускорения prefill компакции.
4. **Compact-промпт:** оставить как есть (B1 не трогает компакцию; `<|think_off|>` в компакции — правильно).

---

## 5. Открытые вопросы / расхождения

1. **MAX_OUTPUT_TOKENS 20000 vs 10000** — какой реально живёт (прецедент settings vs env) → порог компакции.
2. **SESSION-ERROR «Claude Code returned an error result: success»** (tetris-028-re, rc=1) —
   похоже на edge-case SDK (`claude_agent_sdk/query.py:965`), НЕ loop. Открыто, отдельно.
3. **Прокси 8118:** станок на main-пути бьёт напрямую в SERVER_URL; http_proxy=8118 только для
   cloud-ревьюера. Проверить, что main-путь не тянет прокси (влияние на латентность).
4. **CLAUDE_AUTOCOMPACT_PCT_OVERRIDE=95** — подтвердить намерение (агрессивная компакция раньше).

---

## 6. План верификации

1. Накатить B1 на source + bundle; `node --check`; git-коммит (отдельный, ревьюером).
2. Прогнать небольшой FIX-тикет через станок; из probe: post-tool ходы имеют краткое думание,
   error-ходы — краткое думание + восстановление tool_use, финальный ответ — думание есть;
   elapsed не хуже базы (>+10% — стоп).
3. Прогнать длинную сессию → компакция срабатывает (лог), качество summary (аудит), reuse%.
4. Если нужен xhigh-финал: A/B варианта B2 (шаблон без префикса + инструкция).

---

## 7. Файлы для правки (если B1)

- `~/git/claude-code-2.1.88/source/src/utils/messages.ts` (~строки 2194-2220) — логика инъекции.
- `~/git/claude-code-2.1.88/cli.js` — та же правка в minified `bP` (около offset 9708550).
- Ничего на сервере не трогаем (шаблон/флаги остаются как есть).
