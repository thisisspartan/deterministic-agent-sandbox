# СРЕЗ: B1 `<|think_low|>` применён и проверен на проводе (2026-09-01)

Статус: **ПРИМЕНЕНО + ЗАКОММИЧЕНО** (`0e0f6cd` think_low → `44740cd` think_medium в `~/git/claude-code-2.1.88`, ветка `main`).
Решение оператора: вариант B1 (из `PLAN-fix-thinking-final-errors-compact.md`), маркер **`<|think_medium|>`** после живого замера.
Wire-тест пройден (на think_low; medium замерен отдельно на /v1/messages).
Боевой прогон через станок — НЕ делался (см. §5, остаётся за оператором/более мощной моделью).

## 1. Что изменено

`source/src/utils/messages.ts` (и minified `bP` в `cli.js`):

```js
// ТЕКУЩЕЕ (стек/THINK-OFF):
if (trBlocks.length > 0 &&
    !trBlocks.some(b => b.is_error) &&   // ошибки маркера НЕ получали
    !hasMarker) {
  append { type:'text', text:'<|think_off|>' }  // думание OFF до конца задачи
}

// B1 (финал: think_medium):
if (trBlocks.length > 0 && !hasMarker) {
  append { type:'text', text:'<|think_medium|>' }  // думание ON, bounded, на КАЖДЫЙ tool_result
}
// hasMarker теперь ловит: think_off | think_on | think_low | think_medium | think_xhigh
```

Ключевые изменения:
- Убран гейт `!trBlocks.some(b => b.is_error)` → маркер получают и ok, и error tool_result.
- Маркер `<|think_off|>` → `<|think_medium|>` (thinking=true, effort=medium).
- Идемпотентность расширена на все 5 маркеров (иначе накопление).
- Первый планирующий ход (нет tool_result) не тронут → остаётся xhigh.
- `node --check cli.js` → OK.

## 2. Эвиденс wire-теста (`/tmp/cc-b1test/wire.log`)

Логирующий proxy `localhost:9011 → 192.168.8.131:8080`; прогон `claude -p` из `/tmp/cc-b1test`
(промпт: Glob *.py → Read a.py → сообщить первую строку). Ответ верный (файлы перечислены,
первая строка доложена).

Каждый REQUEST `/v1/messages`:

```
[0] role=user  markers=[]                        <- планирующий ход: без маркера (xhigh)
[1] role=assistant  markers=[]
[2] role=user tool_result(err=False), text='<|think_low|>' markers=['<|think_low|>']
  -> upstream 200 resp_bytes=4031
[2] role=user tool_result(err=False), text='<|think_low|>' markers=['<|think_low|>']
[4] role=user tool_result(err=False), text='<|think_low|>' markers=['<|think_low|>']
  -> upstream 200 resp_bytes=9795
```

Вывод:
- Маркер реально уходит на провод в каждом tool_result-батче (в wire-тесте был think_low; после переключения на think_medium проводка та же — меняется только строка текста).
- err=False во всех батчах (тест без ошибок; error-путь покрыт живым замером ниже).
- Think_off в этом прогоне не встречается на tool-ходах (остался только в компакт-промпте).

## 3. Живые замеры думания (2026-09-01, `/v1/messages`)

| Сценарий | Думание | Примечание |
|---|---|---|
| plain user | THINK=59 | планирование xhigh |
| tool_result ok без маркера | THINK=86 | защёлка true (свежий ctx) |
| tool_result error без маркера (свежий ctx) | THINK=296 + TOOL_USE | думает |
| tool_result + `<|think_off|>` (старый клиент) | **НЕТ** | структурное выключение |
| **error ПОСЛЕ предыдущего think_off** | **НЕТ** | **защёлка false → баг оператора** |
| error + `<|think_on|>` | THINK=788 (бюджет выест) | причина loop dec2911 |
| **error + `<|think_low|>`** | **THINK=136 + чистый текст** | **B1 фикс** |
| tool_result + `<|think_low|>` | THINK=100 + текст | дёшево |
| tool_result + `<|think_on|>` | THINK=86 | включено |

### 3а. Сравнение medium vs low (замер 2026-09-01, error tool_result, модель перезапускает тул)

| Маркер | thinking_len | вывод | stop_reason |
|---|---|---|---|
| `think_medium` | **458** | `<tool_call>` Glob `**/*.py` (93 симв.) | end_turn |
| `think_low` | **402** | `<tool_call>` Glob `**/*.py` (93 симв.) | end_turn |

Оба bounded, оба чисто восстанавливаются после ошибки, без loop. `think_medium` = +56 симв. думания
на этом сценарии. Оператор выбрал `think_medium` (чуть глубже думает на тул-ходах/ошибках).

## 4. Связь и состояние

- Коммиты: `55b28d3` (ревёрт think_on) → `0e0f6cd` (B1). Дерево чистое (гейт dirty-tree станка не блокирует).
- CONTEXT.md: добавлена секция «Думание: B1 ...»; отмечено расхождение env MAX_OUTPUT_TOKENS.
- План: `specs/PLAN-fix-thinking-final-errors-compact.md` (§3 B1 подтверждён, B0/B2 отложены).
- Шаблон/сервер НЕ тронуты: `chat_template.jinja.new` + флаги как были.

## 5. Что НЕ сделано / открыто

1. **Боевой прогон через станок** (план §6 п.2): post-tool краткое думание, error-ходы
   восстанавливаются, elapsed не хуже базы (>+10% стоп). Требует живой сервер + время;
   передано оператору / более мощной модели.
2. **MAX_OUTPUT_TOKENS 20000 vs 10000** (settings.stanok.json vs P0-launch.sh) → порог компакции
   76240 vs 86240. Выбрать одно значение.
3. **SESSION-ERROR «Claude Code returned an error result: success»** (tetris-028-re) — отдельно,
   похоже на edge-case SDK.
4. **B2 (xhigh-финал через шаблон)** — если оператор захочет именно xhigh на финальном ответе.
