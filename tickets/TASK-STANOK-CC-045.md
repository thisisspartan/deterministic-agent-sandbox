# TASK-STANOK-CC-045: fire3d — стрелки в application-режиме, чистый выход, диагностика

Модуль: `fire3d`. Файлы: `src/fire3d/ui.js`, `src/fire3d/main.js`,
`tests/fire3d/ui.test.js` (и/или новый `tests/fire3d/keys.test.js`), `docs/fire3d.md`.

## Контекст (что уже есть)

- `ui.js`: `attach(io, fire, opts)` — raw mode, alt-screen (`ESC[?1049h`), скрытый
  курсор, цикл 30 FPS; `stop()` — снять raw mode, показать курсор, `ESC[?1049l`.
  `parseInput(buf, fire)`: одиночные `q`/`Q`/`ESC(0x1b)`/`Ctrl+C(0x03)` → reason;
  CSI `ESC [ D` → `fire.angle -= ROT_STEP`; CSI `ESC [ C` → `fire.angle += ROT_STEP`;
  прочее — игнор. `ROT_STEP = Math.PI/36`.
- `main.js`: TTY → `ui.attach` + `onQuit` (stderr-сообщение + exit 0); SIGINT/SIGTERM;
  non-TTY → `renderStatic` 10 кадров; флаг `--frame` — один кадр после 30 `step()` + exit 0.
- `fire3d.js`: `render(state, width, angle, opts{rows, color256})`.

## Текущее состояние (ПРОВЕРЕНО — требования НЕ выполнены, реализация обязательна)

- `parseInput` (ui.js, строки ~28–44) обрабатывает ТОЛЬКО CSI `ESC [ C` / `ESC [ D`;
  последовательности `ESC O C` / `ESC O D` (application mode) сейчас игнорируются —
  `fire.angle` НЕ меняется.
- `stop()` (ui.js, строки ~114–125) пишет только `CURSOR_SHOW + ALT_OFF` — область
  кадра НЕ очищается.
- `main.js` НЕ пишет баннер возможностей в stderr и НЕ имеет try/catch вокруг `start()`.
- Файла `tests/fire3d/keys.test.js` НЕ существует.

Если тесты тикета проходят БЕЗ изменения кода — это дефект: сначала напиши тесты,
прогони их через Bash — они должны УПАСТЬ на текущем коде (красная фаза TDD),
только потом реализуй.

## Проблема

1. **Стрелки не работают в терминалах с application cursor key mode (DECCKM on)**:
   терминал шлёт стрелки как `ESC O A` (↑), `ESC O B` (↓), `ESC O C` (→),
   `ESC O D` (←) вместо CSI `ESC [ A/B/C/D`. Текущий парсер понимает только CSI →
   вращение ←/→ молча не работает («не работает»).
2. **Грязный выход**: если alt-screen не поддержан/не сработал, после `stop()` на
   основном экране остаются строки последнего кадра.
3. **Нет диагностики**: пользователь не видит, какие возможности терминала
   определил app (rows/cols/color256), и не может понять причину «чёрного экрана».
4. **Необработанные ошибки при старте** (например, неверный путь запуска →
   MODULE_NOT_FOUND) оставляют raw mode/alt-screen в неопределённом состоянии
   и сыплют сырым стектрейсом.

## Требования

### C1. Парсинг стрелок в обоих режимах (`ui.js`)

`parseInput(buf, fire)` дополнить (текущее поведение НЕ менять):
- `ESC O C` (0x1b 0x4f 0x43) → `fire.angle += ROT_STEP` (→, application mode);
- `ESC O D` (0x1b 0x4f 0x44) → `fire.angle -= ROT_STEP` (←, application mode);
- `ESC O A` / `ESC O B` (↑/↓) → игнор (return null);
- прочие `ESC O x` → игнор.
- Существующие CSI `ESC [ C` / `ESC [ D` — как сейчас.
- Одиночный `ESC` (buf.length === 1, 0x1b) — выход, как сейчас (важно:
  `ESC O ...` — это НЕ одиночный ESC).

### C2. Чистый выход (`ui.js`)

В `stop()` перед `CURSOR_SHOW + ALT_OFF` очистить область кадра:
`CURSOR_HOME` + `rows_screen` строк по `cols` пробелов (join `\n`) + `'\n'` + `CLEAR_TAIL`,
где `rows_screen`/`cols` — те же, что использовались в `render` (вычислить как в
`fire3d.js`: `cols = min(W, floor(columns))`, `rows_screen = min(H, max(2, rows-1))`
при заданном rows, иначе H). Если `rows_screen == rows-1` — без завершающего `\n`
(как в кадре). Это гарантирует чистоту даже без alt-screen.

### C3. Баннер возможностей (`main.js`)

До входа в alt-screen (до `ui.attach`) написать в **stderr** одну строку:
`fire3d: <W>x<H> rows=<R> cols=<C> color256=<yes|no>`
(R/C — `process.stdout.rows`/`columns` или `?` если undefined).
Для `--frame` и non-TTY `renderStatic` баннер НЕ писать.

### C4. Защита от ошибок старта (`main.js`)

Обернуть тело `start()` в try/catch: при ошибке — best-effort восстановление
(`process.stdin.setRawMode(false)` в try/catch, `process.stdout.write(CURSOR_SHOW + ALT_OFF)`
в try/catch), затем `process.stderr.write('fire3d: ' + (e.message || e) + '\n')`
и `process.exit(1)`. Без сырого стектрейса.

### C5. Тесты

Создать НОВЫЙ файл `tests/fire3d/keys.test.js` (обязателен; существующие тесты
НЕ удалять) с тестами:
1. `parseInput(Buffer.from([0x1b, 0x4f, 0x43]), fire)` → `fire.angle` вырос на `ROT_STEP`,
   return null.
2. `parseInput(Buffer.from([0x1b, 0x4f, 0x44]), fire)` → `fire.angle` уменьшился на `ROT_STEP`.
3. `parseInput(Buffer.from([0x1b, 0x4f, 0x41]), fire)` → null, angle не изменился (↑).
4. `parseInput(Buffer.from([0x1b, 0x4f, 0x58]), fire)` → null (прочее `ESC O x`).
5. `parseInput(Buffer.from([0x1b, 0x5b, 0x43]), fire)` → как раньше (+ROT_STEP).
6. `parseInput(Buffer.from([0x1b]), fire)` → 'esc' (одинокий ESC не сломан).
7. `stop()` (mock io): в stdout-вывод stop'а входят `CURSOR_HOME` и строки пробелов
   (очистка области) перед `CURSOR_SHOW + ALT_OFF`.
8. `main.js --frame` — как в CC-044 (exit 0, глифы) — регрессия.

### C6. Документация (`docs/fire3d.md`)

Раздел «Управление»: стрелки работают и в normal, и в application cursor key mode
(`ESC [ C/D` и `ESC O C/D`). Раздел «Диагностика»: строка баннера в stderr,
`--frame`.

## Критерии приёмки

- Файл `tests/fire3d/keys.test.js` существует и содержит тесты C5.1–C5.8.
- Все тесты `tests/fire3d/*.test.js` — PASS (`node --test --test-force-exit`).
- `node src/fire3d/main.js --frame` — exit 0, глифы.
- Не менять физику (`fire3d.js` step/create/PRNG), палитру, формат кадра из CC-044.
