# TASK-STANOK-CC-021 — tetris: game (state machine, гравитация, score/level, game-over)

## Контекст

Консольный тетрис, модуль 4 из 6. Зависимости (уже есть): `src/tetris/pieces.js`
(018), `src/tetris/board.js` (019), `src/tetris/bag.js` (020). Специка:
`specs/SPEC-tetris.md` («Геймплей-правила» п.4–9, п.12; «API-контракты → 021»).
Не трогать существующие модули станка и pieces/board/bag (только читать как зависимости).

## Требования

1. Файл `src/tetris/game.js` (CommonJS).
2. `newGame({ seed, now })` → game-объект. `now` = функция `() => ms` (инъекция времени;
   по умолчанию `() => 0` для тестов — НИКАКОГО `Date`/`setInterval` внутри).
   Инициализация: board=newBoard(), bag=newBag(seed), score=0, lines=0, level=1,
   over=false, paused=false, spawn первой фигуры (SPAWN), next=bag.peek().
3. Состояние `game.state` (или поля game): `{ piece, state, col, row, board, score,
   lines, level, next, over, paused }`.
4. `game.tick(dt)` — dt в мс (накопление). Логика:
   - Если over/paused — не делать ничего (return).
   - Накопить `acc += dt`; пока `acc >= dropInterval(level)`: `acc -= dropInterval`,
     попытка мягкого шага вниз (если коллизия — фигура на месте, шаг не сдвигает).
   - `dropInterval(level) = max(80, 800 - level*70)`.
   - После каждого успешного шага вниз/фиксации — проверить lock (см. 5).
5. Движение/поворот/дроп (все проверяют коллизию через pieces.collides):
   - `game.move(dir)` dir∈{−1,+1}: сдвинуть col, если не коллизия.
   - `game.rotate(dir)` dir∈{'CW','CCW'}: вызвать pieces.rotate; если null — не менять.
   - `game.softDrop()`: 1 шаг вниз если можно; score += 1 (за клетку).
   - `game.hardDrop()`: мгновенно вниз до упора; score += 2*cells; затем lock.
6. **Lock + line-clear + score/level** (после hardDrop или когда гравитация не может
   сдвинуть вниз — lock-delay упрощённо: фиксация при попытке шага вниз в коллизии):
   - `board.lock(...)` → {board, clearedRows n}.
   - Очки: `score += [0,100,300,500,800][n] * level` (СТАРЫЙ level, до инкремента).
   - `lines += n`; `level = floor(lines/10) + 1`.
   - **Lock-out:** если зафиксированная фигура имела ≥1 клетки в row 0–1 ПОСЛЕ clear →
     `over = true`.
   - Spawn следующей (next → текущая, next = bag.peek()); если spawn коллизит → over.
7. `game.pause()` / `game.resume()`: paused flag; при паузе сброс DAS/soft-таймеров
   (в game — сброс `acc=0` и soft-drop-счётчика).
8. `game.reset(newSeed)`: полный сброс (board/score/lines/level/bag/over/paused),
   новый seed, spawn. (Используется R в main.)
9. Чистый модуль: НЕ импортировать `process`/`readline`/`setInterval`/`Date`.
   Время — только через `now()`/`dt`.

## Тесты (`tests/tetris/game.test.js`, `node --test`)

- Spawn: после newGame фигура = SPAWN, next = bag.peek().
- Гравитация: tick(dropInterval) → row+1; tick(меньше) → row не изменился.
- dropInterval: level 1 → 730мс; level 9 → 80мс (max); level 10 → 80мс.
- move: влево/вправо меняют col; у стены — не меняют.
- rotate: CW меняет state; у стены — wall-kick (col/row смещены по kick).
- softDrop: row+1, score+1.
- hardDrop: фигура на дне, score += 2*cells, lock произошёл (клетки в board).
  ВАЖНО: после hardDrop → lock → spawn СЛЕДУЮЩЕЙ фигуры (п.6), поэтому `game.col/row`
  после вызова — это уже SPAWN-позиция НОВОЙ фигуры, а не упавшей. Тест должен
  снапшотнуть `{col,row}` упавшей фигуры ДО hardDrop и проверять клетки board
  по этим координатам (НЕ по game.col/game.row после вызова).
- Line-clear: заполнить ряд кроме 1 клетки, hardDrop фигуры которая заполнит →
  n=1, score += 100*level, lines+1, ряд удалён.
- Level-up: lines 9→10 → level 1→2; очки clear на границе — СТАРЫЙ level (тест 9→10).
- Lock-out: зафиксировать фигуру в row 0–1 → over=true.
- Top-out: spawn коллизит (заполнить верх) → over=true.
- pause: tick во время paused не двигает; resume — продолжает.
- reset: после reset(2) score=0, lines=0, level=1, новая фигура.

## Критерии приёмки

- `node --test tests/tetris/game.test.js` — все зелёные.
- `src/tetris/game.js` не импортирует `process`/`readline`/`setInterval`/`Date`.
- Git diff — только `src/tetris/game.js`, `tests/tetris/game.test.js` (+ docs/tetris.md).
- pieces.js/board.js/bag.js не изменены.
