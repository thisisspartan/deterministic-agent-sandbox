# TASK-STANOK-CC-022 — tetris: ui (ANSI-рендер, raw-mode ввод, DAS, FPS-цикл)

## Контекст

Консольный тетрис, модуль 5 из 6. Зависимость: `src/tetris/game.js` (021) + pieces (018).
Специка: `specs/SPEC-tetris.md` («UI / ввод», «API-контракты → 022», п.10–13).
Не трогать существующие модули станка и game/pieces/board/bag.

## Требования

1. Файл `src/tetris/ui.js` (CommonJS). Две части (DI-граница):
   - **`render(frame) → string`** — ЧИСТАЯ функция. `frame` = снапшот
     `{ board, piece, state, col, row, score, lines, level, next, over, paused }`.
     Возвращает ANSI-строку: поле 10×22 (видимые row 2–21 + активная фигура) + HUD
     (score/lines/level) + next-превью (1 фигура). Пустая клетка = `·` или пробел,
     занятая = `█`, активная фигура = `█` (можно другим цветом ANSI).
     Оверлей: `paused` → «PAUSED» по центру; `over` → «GAME OVER» + score/lines/level
     + «R — заново, Q — выход».
   - **`attach(io, game, { now })` → { stop }`** — тонкий слой: `io` = `{ stdin,
     stdout, columns }` (DI, не process напрямую). Включает raw-mode на `io.stdin`,
     polling ввода, DAS, 30 FPS цикл (33мс), каждый кадр: `game.tick(dt)` +
     `io.stdout.write(render(gameSnapshot(game)))`. `stop()` — raw-mode off, курсор
     показать, остановить цикл.
2. **Ввод** (клавиши из спеки): `←`/`→` move, `↓` softDrop, `↑`/`X` rotate CW,
   `Z` rotate CCW, `Space` hardDrop, `P` pause/resume, `Q` quit (вызвать `onQuit`),
   `R` reset (только если over).
3. **DAS:** задержка 170мс, затем автоповтор каждые 50мс в то же направление.
   DAS НЕ начисляет очки (вызывает game.move, не softDrop).
4. **Resize/узкий терминал:** если `io.columns < needed` — render clamp'ится
   (не crash). Тест: render на узком frame не бросает исключение.
5. `now` — инъекция времени (по умолчанию `() => 0`); внутри attach — только через
   `now()`, без `Date` напрямую (для тестов).
6. Чистота: `render` НЕ трогает io/process. `attach` — единственный модуль с raw-mode.

## Тесты (`tests/tetris/ui.test.js`, `node --test`)

- `render` на пустом frame → строка содержит «score»/«0», поле 10 колонок.
- `render` с фигурой → клетки фигуры присутствуют в строке.
- `render` paused → содержит «PAUSED»; over → содержит «GAME OVER».
- `render` на узком frame (columns=10) → не бросает исключение, возвращает string.
- `attach` с mock-io (записывает в массив) + mock-game: симуляция кадров →
  stdout получил ≥1 render; stop() остановил цикл.
- DAS: mock — удержание ← → после 170+50мс game.move(−1) вызван ≥2 раза.
- Ввод: mock stdin пишет escape-последовательность ← → game.move(−1) вызван.

## Критерии приёмки

- `node --test tests/tetris/ui.test.js` — все зелёные.
- `render` не импортирует/не трогает process (чистая функция).
- Git diff — только `src/tetris/ui.js`, `tests/tetris/ui.test.js` (+ docs/tetris.md).
- game.js/pieces.js/board.js/bag.js не изменены.
