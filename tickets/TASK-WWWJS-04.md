# TASK-WWWJS-04: freshTaskState() — полный сброс состояния таска

Supervisor-executed (www.js на 192.168.8.131, не машина).

## Проблема (баги 1 и 3 из ревью)

1. `mtpAccepted`/`mtpGenerated` не входят ни в начальное `state.task` (:49-69),
   ни в сброс `initNewTask` (:116-157). Таск B без MTP-строк наследует цифры
   таска A: DONE/CANCEL-запись берёт `state.task.mtpAccepted || null`
   (:482-483, :558-559), а 59 — truthy → в истории у B чужая MTP-статистика.
2. `lastStallWarnSec` — модульная переменная (:578), не сбрасывается в
   `initNewTask`. Таск B после застывшего A пропускает stall-предупреждение
   на 120с (`elapsedSec !== lastStallWarnSec` → false), первое срабатывание
   на 180с вместо 120с.

## Изменения (~/www.js)

1. Новая функция `freshTaskState()` — декларативный объект ВСЕХ полей
   `state.task` (текущий список :49-69 + `mtpAccepted: null,
   mtpGenerated: null`). Единственный источник формы таска.
2. Начальное `state.task` в `const state = {...}` (:49) → `task: freshTaskState()`.
3. `initNewTask` — полная замена: `state.task = freshTaskState()`, затем
   присвоение `id`, `totalPrompt`, `fromHostRam` (как сейчас :119-124) и
   публикация LCP (:126-136) без изменений. Полевые сбросы :138-156
   удаляются (их заменяет замена).
4. `initNewTask`: `lastStallWarnSec = 0;` (сброс между тасками).

## Acceptance

- Локальный тест на реальных строках: таск A с MTP-строкой (mtpAccepted=59)
  → DONE A несёт 59; таск B без MTP-строк → DONE B несёт `mtpAccepted: null`
  (не 59).
- Локальный тест: после таска с `lastStallWarnSec = 120` новый таск стартует
  с `lastStallWarnSec = 0`.
- Регрессия: существующие тесты (ngram 10/10, ram-est 20/20) зелёные.
- Live: HTTP 200, /api/state task без мусорных полей; история новых тасков
  без чужих MTP-цифр.
