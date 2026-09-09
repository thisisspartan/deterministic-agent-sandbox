# TASK-STANOK-CC-048: fire3d — флаг `--seed N` (воспроизводимый прогон) + общий `src/rng.js`

Модуль: `fire3d`. Файлы: `src/fire3d/main.js` (ИЗМЕНЕНИЕ), `src/fire3d/fire3d.js`
(ИЗМЕНЕНИЕ), `tests/fire3d-seed.test.js` (НОВЫЙ), `docs/fire3d.md` (ИЗМЕНЕНИЕ).

## Контекст (что уже есть)

- Проект — чистый Node.js без внешних зависимостей.
- `src/fire3d/fire3d.js` — физика + рендер. `create(opts)` возвращает state
  `{ heat: Float32Array, W, H, D, angle, rng, decay, srcMask, step }`.
  `opts.seed` — seed PRNG; `opts.rng` — инжект своей PRNG-функции.
  ВНИМАНИЕ: в `fire3d.js` СЕЙЧАС есть ВСТРОЕННЫЙ `mulberry32` (локальная функция) —
  его нужно УБРАТЬ и заменить общим модулем.
- `src/rng.js` — общий детерминированный сид-PRNG (модуль CC-046):
  экспортирует `mulberry32(seed)` (возвращает функцию `() => [0,1)`),
  `randInt`, `pick`, `shuffle`.
- `src/fire3d/main.js` — entry point: `start()` (TTY-режим), `renderStatic(stdout, frames, opts)`
  (non-TTY: N кадров и exit 0), `renderOneFrame(stdout, opts)` (флаг `--frame`).
  Сейчас ВСЕ три пути сеют `Date.now()`. Файл import-safe
  (`require.main === module` guard, есть `module.exports`).
- Тесты: single-file. Существующие тесты `tests/fire3d/*.test.js`
  (keys, perf, physics, render, robustness, ui) — НЕ ТРОГАТЬ, они должны
  продолжать проходить.

## Текущее состояние (ПРОВЕРЕНО — требования НЕ выполнены, реализация обязательна)

- Файла `tests/fire3d-seed.test.js` НЕ существует.
- В `main.js` НЕТ функции `parseSeed` и НЕТ флага `--seed`.
- `fire3d.js` НЕ использует `src/rng.js` (дублирует PRNG внутри себя).

Если тесты тикета проходят БЕЗ изменения кода — это дефект: сначала напиши тесты,
прогони их через Bash — они должны УПАСТЬ на текущем коде (красная фаза TDD:
`parseSeed` не существует → TypeError), только потом реализуй.

## Требования

### C1. `parseSeed(argv)` (`src/fire3d/main.js`)

- Чистая функция, экспортируется в `module.exports`.
- `argv` — массив строк (вид `process.argv`, с префиксом node/скрипт).
- Ищет флаг `--seed` и следующее значение:
  - `--seed 42` → возвращает `42` (число).
  - `--seed 0` → возвращает `0`.
  - Флаг отсутствует → возвращает `undefined`.
  - `--seed` без значения (конец массива) → бросает `RangeError`.
  - Значение не целое (`abc`, `1.5`, `1e3`) → бросает `RangeError`.
  - Значение отрицательное (`-5`) → бросает `RangeError`.
- Не должна ничего печатать и иметь side effects.

### C2. Использование seed во всех путях (`src/fire3d/main.js`)

- `start()`: один раз `const seed = parseSeed(process.argv);`
  - интерактивный путь: `create({ seed: seed !== undefined ? seed : Date.now() })`;
  - non-TTY путь: передать seed в `renderStatic(..., { ...opts, seed })`;
  - `--frame` путь: передать seed в `renderOneFrame(..., { ...opts, seed })`.
- `renderStatic(stdout, frames, opts)`: `opts.seed` — если определён,
  `create({ seed: opts.seed })`, иначе `Date.now()` (текущее поведение).
- `renderOneFrame(stdout, opts)`: аналогично `opts.seed`.
- Без флага `--seed` поведение НЕ меняется (seed = `Date.now()`).

### C3. Общий PRNG (`src/fire3d/fire3d.js`)

- Удалить встроенную локальную функцию `mulberry32` из `fire3d.js`.
- `const { mulberry32 } = require('../rng.js');`
- `create(opts)`: `opts.rng` (инжект) сохраняется; иначе
  `mulberry32(options.seed !== undefined ? options.seed : DEFAULT_SEED)`
  из общего модуля.
- Последовательность `create({ seed: N })` должна быть идентична
  последовательности `mulberry32(N)` из `src/rng.js` (поэлементно `===`).
- `DEFAULT_SEED` и остальная физика — без изменений.

### C4. Тесты (`tests/fire3d-seed.test.js` — НОВЫЙ файл, обязателен)

Использовать `const { test } = require('node:test')` и `require('node:assert')`.
Тесты (все детерминированные; для скорости физики использовать малую сетку,
например `create({ W: 12, H: 8, D: 12, seed: ... })`):

1. `parseSeed(['node', 'fire3d', '--seed', '42'])` → `42`.
2. `parseSeed(['node', 'fire3d'])` → `undefined`.
3. `parseSeed(['node', 'fire3d', '--seed', '0'])` → `0`.
4. `parseSeed(['node', 'fire3d', '--seed'])` → бросает `RangeError` (assert.throws).
5. `parseSeed(['node', 'fire3d', '--seed', 'abc'])` → бросает `RangeError`.
6. `parseSeed(['node', 'fire3d', '--seed', '-5'])` → бросает `RangeError`.
7. `parseSeed(['node', 'fire3d', '--seed', '1.5'])` → бросает `RangeError`.
8. Детерминизм: два `create({ W: 12, H: 8, D: 12, seed: 42 })`, по 100 `step()`
   → `heat` поэлементно равны (Float32Array, `assert.deepStrictEqual` или
   поэлементный `===`).
9. Разные seed: `create({ W: 12, H: 8, D: 12, seed: 42 })` и
   `create({ W: 12, H: 8, D: 12, seed: 43 })`, по 50 `step()` → `heat` НЕ равны
   (есть хотя бы одна отличающаяся ячейка).
10. Общий PRNG: `create({ W: 12, H: 8, D: 12, seed: 42 }).rng` (свежий, без step)
    и `mulberry32(42)` из `require('../src/rng.js')` — первые 100 значений
    поэлементно `===`.
11. `renderStatic` детерминирован по seed: фейковый stdout
    `{ columns: 60, write: (s) => { out += s; } }`; два вызова
    `renderStatic(fake, 5, { seed: 7 })` → собранные строки идентичны.

### C5. Документация (`docs/fire3d.md` — ИЗМЕНЕНИЕ)

- Добавить раздел «Seed / Воспроизводимость»: флаг `--seed N` (N — целое ≥ 0),
  без флага seed = `Date.now()`; PRNG — общий модуль `src/rng.js` (mulberry32);
  один seed + одна последовательность `step()` → идентичные кадры.

## Критерии приёмки

- `tests/fire3d-seed.test.js` существует и содержит тесты C4.1–C4.11.
- Все тесты PASS: новый файл И все существующие `tests/fire3d/*.test.js`.
- `parseSeed` экспортируется из `src/fire3d/main.js`.
- В `src/fire3d/fire3d.js` НЕТ локального определения `mulberry32`
  (используется `require('../rng.js')`).
- НЕ менять существующие тесты `tests/fire3d/*.test.js` и другие модули
  (`fire`, `tetris`, `rng`, `slug` и др.).
