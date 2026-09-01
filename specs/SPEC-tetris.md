# SPEC-tetris — консольный тетрис (Node.js, без внешних зависимостей)

Грилл: 2026-08-31, L1-супервайзер (самогрилл, оператор разрешил автономно).
Red-team: пройден (18 дыр закрыто, см. «Решения red-team» + зафиксированные таблицы/API ниже).

## Цель

Играть в классический тетрис в терминале: 7 tetromino, гравитация, повороты (SRS),
line-clear, score/level/lines, game-over. Управление клавишами. Запуск:
`node src/tetris/main.js`.

## Стек и инварианты

- Node.js ≥18, **без внешних npm-зависимостей** (только stdlib: `process`, `readline`/raw-mode).
- Код в `stanok/src/tetris/`, тесты в `stanok/tests/tetris/`, доки в `stanok/docs/tetris.md`.
- Чистые ядро-модули (pieces/board/bag/game) НЕ импортируют `process`/`readline`/`setInterval` —
  только `ui.js`/`main.js` (DI-граница). Время в `game.js` — инъекция `now()` (тесты без реального таймаута).
- Тесты: `node --test tests/tetris/` (stdlib test-runner, как у станка).
- Не трогать существующие модули станка (`src/*.js` корня, `tests/*` корня) — только подпапки `tetris/`.
- Level **без cap** (Number безопасен до 2^53; dropInterval упирается в пол 80мс на level 9+).

## Геймплей-правила (критерии приёмки)

1. **Поле:** 10 колонок × 20 видимых рядов (+ 2 скрытых ряда сверху для спавна, всего 22).
2. **Фигуры:** все 7 tetromino (I, O, T, S, Z, J, L), каждая = 4 клетки, координаты
   относительно центра/якоря. Отображение — Unicode-блоки (`█` / `▓` / цвет ANSI).
3. **Спавн:** absolute-клетки `(col,row)`, col 0–9, row 0 = верхний скрытый ряд
   (row 0–1 скрытые, row 2–21 видимые). Спавн = SRS-ориентация A (spawn-state):
   - I: (3,0)(4,0)(5,0)(6,0) · O: (4,0)(5,0)(4,1)(5,1)
   - T: (3,1)(4,1)(5,1)(4,0) · S: (3,0)(4,0)(4,1)(5,1)
   - Z: (4,0)(5,0)(3,1)(4,1) · J: (3,0)(3,1)(4,1)(5,1) · L: (5,0)(3,1)(4,1)(5,1)
   Если спавн пересекается с занятыми клетками → **game over**.
4. **Движение:** влево/вправо — 1 колонка за нажатие (hold = повтор через DAS, см. UI).
   Вниз — soft drop (ускоренная гравитация, +1 очко за клетку). Жёсткое падение
   (hard drop) — мгновенно вниз до упора, +2 очка за клетку. DAS-автоповтор очков НЕ даёт.
5. **Поворот:** SRS (Super Rotation System) с wall-kicks. Kick-таблицы зафиксированы
   числами ниже (см. «SRS kick-таблицы»). Поворот, упирающийся в стену/дно/клетки,
   смещается по kick-таблице (перебор вариантов, первый валидный); если ни один
   kick не валиден — поворот отклонён. API: `rotate(state, dir)` внутри pieces.js.
6. **Гравитация:** фигура падает на 1 ряд каждые `dropInterval(level)` мс.
   `dropInterval(level) = max(80, 800 - level*70)` мс. Level берётся ДО line-clear
   текущего тика; очки line-clear — `* level` СТАРОГО уровня (до инкремента).
   Тест на границе 9→10 lines обязателен.
7. **Line-clear:** после фиксации фигуры все полностью заполненные ряды удаляются,
   ряды сверху сдвигаются вниз. Очки: `[0, 100, 300, 500, 800][n] * level`.
   Lines: `+= n`. Level: `floor(totalLines / 10) + 1` (level ≥ 1 всегда).
8. **Next-превью:** 1 фигура (не очередь). Bag-7: мешок из 7 tetromino,
   перемешивается алгоритмом **Fisher-Yates** с PRNG **mulberry32(seed)**;
   детерминированно при seed. `bag.peek()` (не тратит) + `bag.next()` (тратит)
   + `bag.reset(seed)`. После game-over preview замораживается; `R` перемешивает.
9. **Game over:** (а) спавн пересекается; (б) **lock-out** — зафиксирована фигура,
   у которой ≥1 клетки в скрытых рядах (row 0–1) ПОСЛЕ line-clear. Экран game over:
   score/lines/level + «R — заново, Q — выход».
10. **Пауза:** P — пауза/резюм (оверлей «PAUSED»). При паузе DAS/soft-drop таймеры
    СБРАСЫВАЮТСЯ (не continuation). Гравитация на паузе не идёт.
11. **Выход:** Q — в любой момент (в т.ч. из паузы/game-over), терминал возвращается
    в нормальный режим (raw-mode off, курсор виден). SIGINT/SIGTERM — тот же cleanup
    (обработчики в main.js; тест «tty восстановлен после SIGINT»).
12. **R (рестарт):** только из game-over. Новый seed (Date.now()), полный сброс
    score/level/lines/bag/board, preview перемешивается.
13. **Resize/узкий терминал (<~44 col):** не поддерживается, но НЕ crash —
    render clamp'ится, тест «render на width<needed не бросает исключение».

## UI / ввод

- Рендер: ANSI-экран, перерисовка всего поля каждый кадр (дифф не обязателен).
  Поле + HUD (score/level/lines/next) в одном блоке, без «мусора» в терминале
  (использовать `\x1B[H` + очистка блока, либо ANSI-инверсия; конкретика — в тикете UI).
- Ввод: raw-mode, non-blocking (polling `process.stdin`), клавиши:
  `←` `→` (движение), `↓` (soft drop), `↑`/`X` (поворот CW), `Z` (CCW),
  `Space` (hard drop), `P` (пауза), `Q` (выход), `R` (рестарт из game-over).
- DAS (Delayed Auto Shift): повтор движения через 170 мс задержки, затем каждые 50 мс
  (hold = движение до стены).
- Кадр UI: 30 FPS (33 мс) — достаточно для DAS/гравитации; логика не зависит от FPS.

## Нарезка на тикеты (порядок = зависимости)

| # | Модуль | Файл | Зависимости |
|---|--------|------|-------------|
| 018 | `pieces` — 7 tetromino + rotations (SRS-состояния) | `src/tetris/pieces.js` | — |
| 019 | `board` — сетка 10×22, коллизии, lock, line-clear, score/level/lines | `src/tetris/board.js` | 018 |
| 020 | `bag` — 7-bag randomizer (seed-детерминированный) | `src/tetris/bag.js` | — |
| 021 | `game` — state machine (spawn/move/rotate/drop/lock/clear/level/over), dropInterval | `src/tetris/game.js` | 018,019,020 |
| 022 | `ui` — ANSI-рендер поля+HUD+next, raw-mode ввод, DAS, FPS-цикл | `src/tetris/ui.js` | 021 |
| 023 | `main` — сборка, запуск, рестарт/выход, smoke e2e | `src/tetris/main.js` | 021,022 |

Каждый тикет самодостаточен: контекст, требования, критерии приёмки, тесты.
Тесты каждого модуля — чистые unit (без `process`/`readline`), кроме 022/023
(там — контрактные: UI-рендер в строку, main — smoke «запустил и не упал»).

## SRS kick-таблицы (зафиксировано числами)

Ориентации: A (spawn), R (CW), D (180), L (CCW). Kick = (dCol, dRow), row+ = вниз.
Таблица для перехода from→to. Перебор по порядку, первый валидный (без коллизии и
в границах) применяется; если none — поворот отклонён.

**JLSTZ** (T, S, Z, J, L):
- A→R: (0,0) (-1,0) (-1,+1) (0,-2) (-1,-2)
- R→A: (0,0) (+1,0) (+1,-1) (0,+2) (+1,+2)
- R→D: (0,0) (+1,0) (+1,-1) (0,+2) (+1,+2)
- D→R: (0,0) (-1,0) (-1,+1) (0,-2) (-1,-2)
- D→L: (0,0) (+1,0) (+1,+1) (0,-2) (+1,-2)
- L→D: (0,0) (-1,0) (-1,-1) (0,+2) (-1,+2)
- L→A: (0,0) (-1,0) (-1,-1) (0,+2) (-1,+2)
- A→L: (0,0) (+1,0) (+1,+1) (0,-2) (+1,-2)

**I**:
- A→R: (0,0) (-2,0) (+1,0) (-2,-1) (+1,+2)
- R→A: (0,0) (+2,0) (-1,0) (+2,+1) (-1,-2)
- R→D: (0,0) (-1,0) (+2,0) (-1,+2) (+2,-1)
- D→R: (0,0) (+1,0) (-2,0) (+1,-2) (-2,+1)
- D→L: (0,0) (+2,0) (-1,0) (+2,+1) (-1,-2)
- L→D: (0,0) (-2,0) (+1,0) (-2,-1) (+1,+2)
- L→A: (0,0) (+1,0) (-2,0) (+1,-2) (-2,+1)
- A→L: (0,0) (-1,0) (+2,0) (-1,+2) (+2,-1)

**O:** kick (0,0) только (поворот O = no-op по клеткам).

## API-контракты (между тикетами)

- **018 pieces.js:** `PIECES` (7 фигур, 4 SRS-состояния, клетки absolute от якоря),
  `SPAWN` (см. п.3), `KICKS` (таблицы выше), `rotate(state, dir)` → новое состояние
  + применённый kick (или null если отклонён), `collides(board, piece, col, row)`.
- **019 board.js:** `newBoard()`, `lock(board, piece, col, row)` → {board, clearedRows},
  `clearLines(board)` → {board, n}, `isFullRow(row)`, `inBounds`.
- **020 bag.js:** `newBag(seed)`, `bag.next()` (тратит), `bag.peek()` (не тратит),
  `bag.reset(seed)`. PRNG = mulberry32, shuffle = Fisher-Yates.
- **021 game.js:** `newGame({seed, now})`, `game.tick(dt)` (накопление dt, гравитация,
  возвращает события), `game.move(dir)`, `game.rotate(dir)`, `game.softDrop()`,
  `game.hardDrop()`, `game.state` (piece/col/row/score/level/lines/next/over/paused).
  Время — только через `now()` (инъекция), без `setInterval`/`Date` внутри.
- **022 ui.js:** `render(frame) → string` (чистый, frame = снапшот game.state),
  `attach(io, game)` (тонкий: raw-mode, polling, DAS, 30FPS, вызывает game.tick(dt)).
  DAS: задержка 170мс, затем 50мс; DAS не начисляет очки.
- **023 main.js:** сборка, SIGINT/SIGTERM cleanup, R/Q, smoke e2e.

## Критерии приёмки (общие)

- `node --test tests/tetris/` — все тесты зелёные.
- `node src/tetris/main.js` — игра запускается, управляется, game over → R/Q работают.
- Нет внешних зависимостей (`package.json` без `dependencies`, либо `dependencies: {}`).
- Существующие модули станка не изменены (git diff — только `tetris/` подпапки + docs).

## Решения red-team (зафиксировано, 18 дыр → закрыто)

1. Kick-таблицы — числами в спеке (раздел «SRS kick-таблицы»), не «в тикете».
2. Spawn — absolute-клетки всех 7 (п.3), тест на них в 018.
3. Bag-7 PRNG = mulberry32 + Fisher-Yates (п.8, API 020); golden-последовательность seed=1 в тикете 020.
4. Lock-out — ≥1 клетки в row 0–1 ПОСЛЕ line-clear (п.9), тесты lock в row 21/22 в 021.
5. dropInterval: level ДО clear; очки clear — СТАРЫЙ level (п.6), тест границы 9→10 в 021.
6. Soft drop +1/клетка за физический тик; DAS не даёт очков (п.4, API 022).
7. R — новый seed, полный сброс, только из game-over (п.12).
8. DAS-счёт вынесен: DAS не начисляет (API 022 + unit-тест).
9. Пауза сбрасывает DAS/soft-таймеры, гравитация стоп (п.10).
10. Resize/узкий терминал — не crash, clamp + тест (п.13).
11. SIGINT/SIGTERM cleanup + тест tty (п.11, 023).
12. tick(dt) с инъекцией now(), накопление остатка (API 021) — timing-тесты без флейков.
13. Top-out + spawn-over-lock — явные тесты в 021.
14. Level без cap, Number до 2^53 (инварианты).
15. Next-preview = 1 фигура, замораживается до R (п.8).
16. rotate(state,dir) с kick-таблицами ВНУТРИ 018 (API 018) — 021 не чинит 018.
17. ui.render(frame) чистый + attach(io,game) тонкий (API 022) — тест на mock-frame.
18. bag.peek()/next()/reset(seed) контракт (API 020) — 021 показывает next-preview.
