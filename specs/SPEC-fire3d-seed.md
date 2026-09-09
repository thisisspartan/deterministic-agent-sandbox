# SPEC-fire3d-seed — fire3d: --seed (воспроизводимый прогон)

## Проблема
fire3d уже детерминирован по seed (встроенный mulberry32 в `src/fire3d/fire3d.js`),
но `main.js` всегда сеет `Date.now()` — конкретный прогон невозможно воспроизвести
из CLI. Модуль `src/rng.js` (CC-046) создан именно для централизации сид-PRNG,
но fire3d его не использует (дублирует PRNG внутри себя).

## Требования
- C1: `parseSeed(argv)` — чистая функция в `main.js` (экспортируется):
  `--seed <N>` → целое ≥ 0; без флага → `undefined`; мусор/отрицательное/нет значения → `RangeError`.
- C2: все три пути `main.js` (интерактив, non-TTY static, `--frame`) используют
  разобранный seed; без флага — `Date.now()` (текущее поведение).
  `renderStatic`/`renderOneFrame` принимают `opts.seed`.
- C3: `fire3d.js` использует общий `require('../rng.js')` (mulberry32 из CC-046),
  встроенный PRNG удалён. Последовательность `create({seed})` идентична
  `rng.mulberry32(seed)`.
- C4: НОВЫЙ плоский тест `tests/fire3d-seed.test.js` (TDD red→green):
  parseSeed (7 кейсов), детерминизм create({seed}), разные seed → разные кадры,
  совпадение с общим rng, детерминизм renderStatic через opts.seed.
- C5: `docs/fire3d.md` — раздел «Seed / Воспроизводимость».

## Ограничения
- НЕ менять существующие тесты `tests/fire3d/*.test.js` (должны продолжать проходить).
- НЕ менять другие модули.
- Тесты — плоский файл (verifier/TDD-гейт работают только с `tests/<mod>.test.js`).

## Критерии приёмки
- `node --test tests/fire3d-seed.test.js` — PASS.
- Все существующие тесты — PASS.
- В `fire3d.js` нет локального определения mulberry32.
- `parseSeed` экспортируется из `main.js`.
