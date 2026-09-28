# TASK-WWWJS-05: pushHistory(extra) — единая запись в историю

Supervisor-executed (www.js на 192.168.8.131, не машина).

## Проблема

DONE-ветка (:525-574) и CANCEL-ветка (:466-503) дублируют конструирование
history-записи (одинаковые поля, включая `mtpAccepted: state.task.mtpAccepted
|| null` и т.д.). Две копии — риск рассинхронизации при изменении формы
записи (как в WWWJS-04).

## Изменения (~/www.js)

1. Новый хелпер `pushHistory(extra)`:
   - строит запись из `state.task` (текущий набор полей DONE-ветки) +
     расширение `extra`;
   - `state.history.unshift(rec)`;
   - `if (state.history.length > MAX_HISTORY) state.history.pop();`
2. DONE-ветка: конструирование записи → `pushHistory({ ... })` (то, что
   уникально для DONE).
3. CANCEL-ветка: → `pushHistory({ cancelled: true, ... })` (то, что
   уникально для CANCEL).
4. Форма записи в истории НЕ меняется (фронтенд :1241/:1252 работает как есть).

## Acceptance

- Локальный тест: DONE-строка → запись в истории с теми же полями, что до
  рефактора (id/time/mtpAccepted/mtpMeanLen/...); CANCEL-строка → запись с
  `cancelled: true`.
- Локальный тест: история обрезается до MAX_HISTORY.
- Регрессия: ngram 10/10, ram-est 20/20, тест WWWJS-04 зелёные.
- Live: HTTP 200, история рендерится (MTP-колонка, CANCEL-тег) без изменений.
