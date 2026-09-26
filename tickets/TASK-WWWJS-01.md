# TASK-WWWJS-01: Отображение отменённых запросов (CANCEL)

Supervisor-executed (www.js на 192.168.8.131, не машина).

## Проблема

Строка `W srv stop: cancel task, id_task = N` (1062 в логе) не парсится:
карточка задачи висит без DONE, в REQUEST HISTORY записи нет, EVENT LOG молчит.

## Изменения (~/www.js)

1. Парсер: ветка `line.includes('cancel task')` → извлечь `id_task = N`.
   - Если tid == текущий task id: событие `CANCEL` (тег CANCEL, красный),
     запись в history с `cancelled: true` и частичными данными
     (input/kvReuse/prefill/decode на момент отмены, speed как есть),
     `currentStage` → IDLE (с той же 1.5s отсечкой, что у DONE).
   - Если tid совпадает с записью в history — backfill `cancelled: true`.
2. CSS: `.log-row.CANCEL` — красная левая граница + красный тег.
3. Карточка задачи: `histItem.cancelled` → статус `CANCELLED ✗` (var(--red)).
4. REQUEST HISTORY: `cancelled` входит в hash рендера; в ячейке SPEED — `✗`
   (вместо t/s) для отменённых.

## Acceptance

- Локальный тест: реальная строка cancel из лога → событие CANCEL +
  history-запись с cancelled: true; чужой tid → не трогает текущий task.
- Live: HTTP 200, в served HTML есть селектор `.log-row.CANCEL` и
  `CANCELLED` в рендере карточки.
