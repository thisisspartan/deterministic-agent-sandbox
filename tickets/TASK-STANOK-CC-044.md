# TASK-STANOK-CC-044: fire3d — устойчивость к «чёрному экрану» в чужих терминалах

Модуль: `fire3d`. Файлы: `src/fire3d/fire3d.js`, `src/fire3d/main.js`, `src/fire3d/ui.js`,
`tests/fire3d/*.test.js`, `docs/fire3d.md`.

## Контекст (что уже есть)

- `fire3d.js`: `create(opts)`, `step(state)`, `render(state, width, angle) -> string`.
  Кадр = `CURSOR_HOME + lines.join('\n') + '\n' + CLEAR_TAIL`, где `CLEAR_TAIL = ESC+'[J'`.
  Каждая ячейка строки пишется со своим цветовым кодом `ESC+'[38;5;'+N+'m'`
  (пустая ячейка — N=234, глиф — пробел), прогон однотонных ячеек мержится,
  в конце ранга — `ESC+'[0m'`. Строки выводятся y = H-1 … 0 (y=0 — базовый слой,
  нижняя строка). `FLAME_GLYPHS = ' .,;:~*oO@'`, `FLAME_MIN = 0.08`, `DARK_BG = 234`.
  Палитра `STOPS` (heat → 256-color): [0.05→160, 0.3→196, 0.5→202, 0.7→214, 0.9→226, 1.0→231].
- `ui.js`: `attach(io, fire, opts)` — raw mode, alt-screen (`ESC[?1049h`), скрытый
  курсор, цикл 30 FPS; `stop()` всегда восстанавливает курсор и alt-screen.
- `main.js`: TTY → `ui.attach`; non-TTY → 10 статических кадров в stdout + exit(0).

## Проблема

В терминалах, отличающихся от эталонных, приложение показывает чёрный экран.
Два механизма:
1. **Высота терминала < H+1 (25 строк)**: завершающий `\n` кадра упирается в
   нижнюю границу и скроллит экран КАЖДЫЙ кадр (30 FPS) — картинка «бежит»,
   верхние (тёмные) строки уходят, визуально — чёрный/мерцающий экран.
2. **Терминал без 256-цветов**: все ячейки окрашены `ESC[38;5;Nm`; терминал без
   поддержки 256-цветов может игнорировать/некорректно обрабатывать SGR —
   пламя становится невидимым.

## Требования

### C1. Адаптация кадра к высоте терминала (`fire3d.js`)

`render(state, width, angle, opts)` — новый 4-й аргумент `opts` (объект, может
быть undefined): `opts.rows` — число строк терминала.
- `rows_screen = min(H, max(2, rows - 1))`; если `rows` не задан/не число → `rows_screen = H`
  (текущее поведение).
- Рисуем НИЖНИЕ `rows_screen` строк пламени: y от `rows_screen - 1` до 0
  (база пламени y=0 всегда видна; верхушка отрезается).
- Формат кадра:
  - если `rows_screen == rows - 1` (кадр заполняет экран до последней строки):
    `CURSOR_HOME + lines.join('\n')` — БЕЗ завершающего `\n` и БЕЗ `CLEAR_TAIL`
    (последняя строка полностью покрыта поячеечными глифами, скролл невозможен);
  - иначе (кадр короче экрана): текущий формат
    `CURSOR_HOME + lines.join('\n') + '\n' + CLEAR_TAIL`.
- `width`/`cols` — без изменений (`min(W, floor(width))`).

### C2. Фолбэк на 16 цветов (`fire3d.js`)

Новая чистая функция `colorCode(h, color256) -> string`:
- `color256 === true` (дефолт): текущее поведение — `ESC+'[38;5;'+N+'m'`,
  N = `colorIndex(h)`, для h<=0 — `DARK_BG` (234).
- `color256 === false`: 16-цветные коды БЕЗ интерполяции (ближайший стоп снизу):
  - h <= 0 → `ESC+'[90m'` (bright black — фон);
  - 0 < h < 0.3 → `ESC+'[31m'` (красный);
  - 0.3 <= h < 0.55 → `ESC+'[91m'` (bright red);
  - 0.55 <= h < 0.8 → `ESC+'[33m'` (жёлтый);
  - h >= 0.8 → `ESC+'[97m'` (белый).
- `render` принимает `opts.color256` (дефолт `true`) и строит коды через `colorCode`.
  Мержинг однотонных прогонов и `ESC[0m` — без изменений.
- Экспортировать `colorCode`.

### C3. Определение возможностей и self-test (`main.js`)

- `color256 = (process.env.COLORTERM || '').toLowerCase() === 'truecolor'
   || /256color/.test(process.env.TERM || '')` — передать в `ui.attach`
  (через opts) и в `renderStatic`.
- `ui.js`: `attach(io, fire, opts)` — `opts.rows` и `opts.color256` пробрасывать
  в `render` (rows по умолчанию из `io.rows`, если задан, иначе `process.stdout.rows`).
- Флаг `--frame` (проверить `process.argv`): отрендерить ОДИН кадр после 30
  вызовов `step()` (пламя разгоревшееся) в stdout и `process.exit(0)` —
  работает и в TTY, и в non-TTY (self-test для пользователя).
- `renderStatic` (non-TTY без флага) — как сейчас, но с `rows`/`color256`.

### C4. Тесты (`tests/fire3d/`)

Дополнить/создать тесты (НЕ удаляя существующие):
1. `render` с `rows = 10` (H=24): кадр = ровно 9 строк (y=8…0), БЕЗ завершающего
   `\n` после последней строки, БЕЗ `ESC[J`; начинается `ESC[H`.
2. `render` с `rows = 50`: 24 строки, ЕСТЬ завершающий `\n` + `ESC[J` (старый формат).
3. `render` без `rows`: как сейчас (24 строки, `\n` + `ESC[J`).
4. `colorCode(0.5, false) === '\u001b[33m'`; `colorCode(0.9, false) === '\u001b[97m'`;
   `colorCode(0.1, false) === '\u001b[31m'`; `colorCode(0, false) === '\u001b[90m'`;
   `colorCode(0.5, true)` содержит `38;5;` (текущая палитра).
5. `render(..., { color256: false })`: в кадре НЕТ подстроки `38;5;`, ЕСТЬ `\u001b[31m`
   и глифы пламени.
6. `node src/fire3d/main.js --frame` (spawn, non-TTY): exit 0, вывод содержит
   глифы из `FLAME_GLYPHS` (не только пробелы).

### C5. Документация (`docs/fire3d.md`)

Добавить: адаптация к высоте терминала, фолбэк 16-цветов (детект по
COLORTERM/TERM), флаг `--frame` для self-test.

## Критерии приёмки

- `node --test --test-force-exit tests/fire3d/physics.test.js` (и остальные
  существующие файлы) — PASS; новые тесты C4 — PASS.
- `node src/fire3d/main.js --frame` в non-TTY — exit 0, видимые глифы.
- Не менять физику (`step`, `create`, PRNG) и управление (стрелки, выход).
