# TASK-STANOK-CC-018 — tetris: pieces (7 tetromino + SRS-состояния + kick-таблицы + rotate)

## Контекст

Начало нового проекта — консольный тетрис (Node.js, без внешних зависимостей).
Спека: `specs/SPEC-tetris.md` (см. разделы «SRS kick-таблицы», «API-контракты → 018»,
«Геймплей-правила» п.3, п.5). Этот тикет — первый модуль: `src/tetris/pieces.js`.
Создаёт подпапку `src/tetris/` (её ещё нет). Не трогать существующие модули станка
(`src/*.js` корня, `tests/*` корня) — только `src/tetris/` и `tests/tetris/`.

## Требования

1. Файл `src/tetris/pieces.js` (CommonJS, `module.exports`).
2. `PIECES` — объект с 7 фигурами `I, O, T, S, Z, J, L`. Каждая = 4 SRS-состояния
   `A` (spawn), `R` (CW), `D` (180), `L` (CCW). Каждое состояние = массив клеток
   `[col, row]` (relative от якоря фигуры; col+ = право, row+ = вниз).
   Спавн-состояние A должно давать absolute-клетки из спеки (п.3) при якоре-смещении:
   - I: A=(3,0)(4,0)(5,0)(6,0) · O: A=(4,0)(5,0)(4,1)(5,1)
   - T: A=(3,1)(4,1)(5,1)(4,0) · S: A=(3,0)(4,0)(4,1)(5,1)
   - Z: A=(4,0)(5,0)(3,1)(4,1) · J: A=(3,0)(3,1)(4,1)(5,1) · L: A=(5,0)(3,1)(4,1)(5,1)
   (Якорь/смещение зафиксировать так, чтобы A-состояние = этим клеткам; остальные
   состояния R/D/L — корректные SRS-повороты этой же фигуры.)
3. `SPAWN` — объект: для каждой фигуры `{ piece, col, row }` spawn-позиция (см. п.3 спеки).
4. `KICKS` — kick-таблицы СRS ЧИСЛАМИ (дословно из спеки, раздел «SRS kick-таблицы»):
   `KICKS.JLSTZ[from][to]` и `KICKS.I[from][to]` — массивы `[dCol, dRow]` по порядку.
   `KICKS.O = { A:{R:[[0,0]]}, ... }` (только (0,0)).
5. `collides(board, piece, state, col, row)` → boolean: true если любая клетка
   (state-клетка + (col,row)) вне границ (col<0, col>9, row>21) или в занятой клетке
   board. (row<0 допустимо — скрытые ряды сверху.)
6. `rotate(piece, fromState, dir, board, col, row)` → `{ piece, state, col, row, kick }`
   или `null` (если все kick-варианты невалидны). dir: 'CW' | 'CCW'.
   - Новый state: A→R→D→L→A (CW), A→L→D→R→A (CCW).
   - O: state не меняется (no-op), kick (0,0).
   - Перебор `KICKS[piece==='I'?'I':'JLSTZ'][from][to]` по порядку; для каждого (dc,dr)
     проверить `!collides(board,piece,newState,col+dc,row+dr)`; первый валидный — результат.
7. Чистый модуль: НЕ импортировать `process`/`readline`/`setInterval`/`Date`.

## Тесты (`tests/tetris/pieces.test.js`, `node --test`)

- Каждая из 7 фигур: 4 состояния × 4 клетки, все клетки внутри reasonable bounds.
- Spawn: `SPAWN[p]` + `PIECES[p].A` дают ровно absolute-клетки п.3 (для всех 7).
- `collides`: вне границ (col<0, col>9, row>21) → true; в занятой клетке → true;
  свободно → false; row<0 (скрытые) → false (не коллизия).
- `rotate` CW: A→R→D→L→A цикл для T (и I).
- `rotate` wall-kick: T у левой стены A→R применяет kick (не (0,0) если (0,0) коллизит).
- `rotate` отклонён: фигура в «яме» где все kick-варианты коллизят → null.
- O: rotate → state не изменился, kick (0,0).
- I: kick-таблица I используется (не JLSTZ).

## Критерии приёмки

- `node --test tests/tetris/pieces.test.js` — все зелёные.
- `src/tetris/pieces.js` не импортирует `process`/`readline`/`setInterval`/`Date`.
- Git diff — только `src/tetris/`, `tests/tetris/` (новые файлы).
- `docs/tetris.md` — создать (если нет) с кратким описанием модуля pieces.
