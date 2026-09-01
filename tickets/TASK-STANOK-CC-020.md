# TASK-STANOK-CC-020 — tetris: bag (7-bag randomizer, mulberry32 + Fisher-Yates)

## Контекст

Консольный тетрис, модуль 3 из 6. Специка: `specs/SPEC-tetris.md`
(«Геймплей-правила» п.8; «API-контракты → 020»). Независим от 018/019.
Не трогать существующие модули станка.

## Требования

1. Файл `src/tetris/bag.js` (CommonJS).
2. `newBag(seed)` → объект bag с методами:
   - `next()` — вернуть и УДАЛИТЬ следующую фигуру (string: 'I','O','T','S','Z','J','L').
     Если мешок пуст — сгенерировать новый (перемешать 7).
   - `peek()` — вернуть следующую фигуру БЕЗ удаления.
   - `reset(seed)` — сбросить bag с новым seed.
3. PRNG = **mulberry32** (зафиксированный алгоритм):
   ```
   function mulberry32(a) { return function() {
     a |= 0; a = a + 0x6D2B79F5 | 0;
     let t = Math.imul(a ^ a >>> 15, 1 | a);
     t = t + Math.imul(t ^ t >>> 7, 61 | t) ^ t;
     return ((t ^ t >>> 14) >>> 0) / 4294967296;
   }; }
   ```
4. Shuffle = **Fisher-Yates** (классический, от конца к началу):
   ```
   for (let i = arr.length - 1; i > 0; i--) {
     const j = Math.floor(rng() * (i + 1));  // j ∈ [0..i]
     swap(arr[i], arr[j]);
   }
   ```
   ВАЖНО: `j = floor(rng()*(i+1))` (НЕ `i`) — это классический вариант;
   `floor(rng()*i)` — баг, не использовать.
5. Детерминированно: `newBag(1).next()` всегда даёт одну и ту же последовательность.
6. Чистый модуль: НЕ импортировать `process`/`readline`/`setInterval`/`Date`.
   Seed — number, передаётся явно (не `Date.now()` внутри).

## Тесты (`tests/tetris/bag.test.js`, `node --test`)

- **Golden-последовательность seed=1:** первые 14 `next()` (2 мешка) равны
  `['Z','I','T','S','L','J','O','Z','L','T','S','O','I','J']` — зафиксировать
  ЭТУ константу в тесте (не пересчитывать «по памяти», не менять порядок).
- `peek()` не тратит: `peek()` === `next()` (первый вызов), затем `next()` тот же.
- 7-bag: первые 7 `next()` = перестановка всех 7 фигур (каждая ровно по 1 разу).
- Второй мешок (8–14) = тоже перестановка всех 7.
- `reset(seed)`: после reset(1) последовательность = как у newBag(1).
- Детерминизм: два newBag(42) дают одинаковые 21 `next()`.
- Все значения ∈ {'I','O','T','S','Z','J','L'}.

## Критерии приёмки

- `node --test tests/tetris/bag.test.js` — все зелёные.
- `src/tetris/bag.js` не импортирует `process`/`readline`/`setInterval`/`Date`.
- Git diff — только `src/tetris/bag.js`, `tests/tetris/bag.test.js` (+ docs/tetris.md).
- Существующие модули станка не изменены.
