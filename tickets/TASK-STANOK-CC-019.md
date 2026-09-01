# TASK-STANOK-CC-019 — tetris: board (сетка 10×22, lock, line-clear, score/level/lines)

## Контекст

Консольный тетрис, модуль 2 из 6. Предыдущий тикет 018 создал `src/tetris/pieces.js`
(PIECES, SPAWN, KICKS, collides, rotate). Специка: `specs/SPEC-tetris.md`
(«Геймплей-правила» п.1, п.7, п.9; «API-контракты → 019»). Не трогать существующие
модули станка и `src/tetris/pieces.js` (только читать как зависимость).

## Требования

1. Файл `src/tetris/board.js` (CommonJS).
2. `newBoard()` → `{ grid }` где `grid` = массив 22 ряда × 10 колонок, `0` = пусто,
   `>0` = занято (значение = id фигуры для цвета). Row 0 = верх (скрытый), row 21 = дно.
3. `inBounds(col, row)` → boolean: `0<=col<10 && 0<=row<22`.
4. `isFullRow(grid, row)` → boolean: все 10 клеток ряда заняты.
5. `lock(board, piece, state, col, row)` → `{ board, clearedRows }`:
   - Записать клетки фигуры (piece+state+col+row) в grid (значением = piece-id).
   - Найти все полные ряды, удалить их, сдвинуть верх вниз, добавить пустой ряд сверху.
   - Вернуть новый board + `clearedRows` (число удалённых рядов).
   - НЕ менять score/level/lines (это делает game.js, тикет 021).
6. `clearLines(board)` → `{ board, n }` — то же что удаление в lock, но отдельной
   функцией (для тестов). `n` = число удалённых рядов.
7. Чистый модуль: НЕ импортировать `process`/`readline`/`setInterval`/`Date`.
   НЕ импортировать pieces.js (board работает с клетками, не с фигурами — DI).

## Тесты (`tests/tetris/board.test.js`, `node --test`)

- `newBoard`: 22×10, все 0.
- `inBounds`: границы (−1, 10, −1, 22) → false; (0,0),(9,21) → true.
- `isFullRow`: пустой ряд → false; заполненный → true.
- `lock`: поставить фигуру на дно → клетки в grid; полный ряд → удалён, `clearedRows=1`;
  верхний ряд после clear = пустой.
- `lock` lock-out: фигура зафиксирована с клетками в row 0–1 → эти клетки в grid
  (game.js решит game-over по ним; board просто фиксирует).
- `clearLines`: 0 рядов → n=0, board не изменился; 4 ряда (tetris) → n=4.
- Сдвиг после clear: клетки выше удалённого ряда сдвинулись на n вниз.

## Критерии приёмки

- `node --test tests/tetris/board.test.js` — все зелёные.
- `src/tetris/board.js` не импортирует `process`/`readline`/`setInterval`/`Date`.
- Git diff — только `src/tetris/board.js`, `tests/tetris/board.test.js` (+ docs/tetris.md).
- Существующие модули станка и `pieces.js` не изменены.
