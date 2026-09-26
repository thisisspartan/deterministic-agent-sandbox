# TASK-WWWJS-03: Жизненный цикл чекпоинтов в панели HOST RAM

Supervisor-executed (www.js на 192.168.8.131, не машина).

## Проблема

Панель HOST RAM показывает только срез `cache state: N prompts, N MiB`.
Оборот чекпоинтов невидим:
- `created context checkpoint N of N` (5426)
- `erased invalidated context checkpoint` (1744)
- `erasing context checkpoint too close to an earlier one` (3147)

## Изменения (~/www.js)

1. State: `ramCache.cpCreated: 0, ramCache.cpErased: 0,
   ramCache.cpCurrent: 0, ramCache.cpMax: 0`.
2. Парсер:
   - `created context checkpoint` → cpCreated++, cpCurrent = N, cpMax = M
     (из «checkpoint N of M»).
   - `erased invalidated context checkpoint` → cpErased++.
   - `erasing context checkpoint too close` → cpErased++.
3. UI: в карточке HOST RAM третья строка:
   `Чекпоинты: <cpCurrent>/<cpMax> | +<cpCreated> / −<cpErased>`.

## Acceptance

- Локальный тест: три реальные строки → счётчики
  (created: cpCreated=1, cpCurrent/cpMax из строки; erased: cpErased=2).
- Live: HTTP 200, в served HTML есть lbl-чекпоинтов; /api/state несёт
  cpCreated/cpErased (растут при активности сервера).
