# TASK-STANOK-CC-039 — fire: самодиагностика (лог всех событий в /tmp/fire-debug.log)

## Контекст
В терминале пользователя огонь живёт ~15 с и умирает от SIGINT (p10k: «INT ✘ 15s»),
при этом пользователь видит статичный кадр («не горит»). Во всех наших PTY-тестах
процесс живёт бесконечно и анимируется. Нужен самодиагностический лог, чтобы по одному
запуску у пользователя понять: (а) жив ли цикл кадров, (б) что приходит на stdin,
(в) какой сигнал/ключ убил процесс и когда.

## Что сделать

### 1. Новый модуль `src/fire/diag.js`
Мини-логгер (без зависимостей):
- `createDiag(path)` → `{ log(msg), path, close() }`.
- `log(msg)` — appendFileSync строки `ISO-время msg\n` в `path`; ВСЕ операции в
  try/catch (лог не должен ронять анимацию).
- При создании файла — ОЧИСТИТЬ его (writeFileSync ''), лог всегда одного запуска.
- Экспорт: `module.exports = { createDiag, DEFAULT_PATH }`, где `DEFAULT_PATH = '/tmp/fire-debug.log'`.

### 2. `src/fire/ui.js` — логирование (опционально, через opts.diag)
- `attach(io, fire, opts)` принимает `opts.diag` (объект из diag.js или undefined —
  без него поведение как сейчас).
- `onKey`: логировать КАЖДЫЙ чанк: `input len=<N> hex=<hex-строка>` (chunk.toString('hex')).
- `frame()`: логировать каждые 30 кадров: `frame #<N>` (N — счётчик кадров).
- `stop()`: лог `stop`.

### 3. `src/fire/main.js` — лог старта/сигналов/выхода
- TTY-путь: создать diag (DEFAULT_PATH), передать в `ui.attach(..., { diag })`.
- Лог `start pid=<pid> columns=<N> fpsMs=33`.
- onQuit: `quit reason=<reason>` (строку на stderr НЕ менять).
- SIGINT-хендлер: лог `signal SIGINT` до exit. SIGTERM-хендлер: лог `signal SIGTERM`.
- В stderr-строку остановки ДОБАВИТЬ путь лога:
  `fire: остановлено (<reason|SIGINT|SIGTERM>), лог: /tmp/fire-debug.log`.
- Non-TTY-путь (renderStatic) — НЕ трогать.

### 4. Тесты
- `tests/fire/diag.test.js` (новый):
  - D1: createDiag создаёт и очищает файл; log() дописывает строку с ISO-временем.
  - D2: ui.attach с mock io + diag: после ввода чанка [0x71] в логе есть
    `input len=1 hex=71` и `quit reason=q` (через main? нет — ui вызывает onQuit,
    лог quit делает main; в тесте ui проверяем только `input ...` и `stop`).
  - D2b: ui.attach с mock io + diag: `frame #N` логируется каждые 30 кадров.
    ВАЖНО (детерминизм): в opts передавай МАЛЕНЬКИЙ `fpsMs` (1–2 мс), чтобы 60
    кадров уложились в <200 мс, и жди с запасом (≥1 с). НЕ полагайся на дефолтные
    33 мс/кадр и короткое ожидание (~400 мс) — 60 кадров при 33 мс = ~2 с, тест
    упадёт (так упал прошлый прогон).
  - D3: без opts.diag — никаких ошибок (старое поведение).
- Существующие `tests/fire/*.test.js` — не ломать.

### 5. `docs/fire.md`
- Раздел «Диагностика»: при TTY-запуске события пишутся в /tmp/fire-debug.log
  (start, frame #N каждые 30 кадров, input hex, stop, signal, quit reason);
  путь лога печатается в строке остановки.

## Критерии приёмки
- A1. `node src/fire/main.js` в PTY создаёт /tmp/fire-debug.log со строками
  `start ...`, `frame #30`, `frame #60`... за ~3 с работы.
- A2. Ввод клавиши q в PTY: в логе `input len=1 hex=71`, `stop`, `quit reason=q`;
  на stderr `fire: остановлено (q), лог: /tmp/fire-debug.log`.
- A3. `node --test` по всем `tests/fire/*.test.js` — PASS.
- A4. Smoke: `bash scripts/run.sh smoke src/fire/main.js` — не падает.

## Ограничения
- Писать только в `src/`, `tests/`, `docs/`.
- Не менять физику/рендер (fire.js) и поведение выходов (типы reason, exit-коды).
- Логгер — только appendFileSync, без таймеров и потоков.
