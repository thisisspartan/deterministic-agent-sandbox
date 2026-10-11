# SPEC-DOOMFIRE — терминальный огонь (PSX Doom Fire) в станке

Заказ оператора 2026-10-11: полный инженерный процесс (spec → tickets →
реализация → self-grilling) на примере консольного огня. Feature-волна,
инфраструктура не трогается (FROZEN не нарушен: это deliverables в
`src/tests/docs`, не механизмы станка).

## 0. Реальное окружение (гриль-факты, проверено на дереве)

- Pod-образ `stanok-machine:latest` (Dockerfile: debian bookworm-slim +
  python3.11 + node из официального tarball + npm). **Сеть в поде закрыта**
  (кроме модельного сервера) → `npm install node-pty` НЕвозможен.
- Решение: headless-PTY проверка (FIRE-05) на **stdlib `pty` Python**
  (`pty.openpty` + spawn + чтение сырых байтов) — эквивалент node-pty без npm.
  Node-ветка примера оператора отброшена осознанно; Python покрывает и рендер,
  и PTY-верификацию.
- TTY-переменные (`TERM=xterm-256color`) выставляет сам PTY-тест при spawn —
  зависимость от env пода убрана.
- Machine-правила (CLAUDE.md): только `src/ tests/ docs/ scripts/run.sh`;
  тесты py → `tests/**/*_test.py` через `scripts/run.sh`; без conftest.py.

## 1. Алгоритм (фиксирован, обязательная семантика)

Классический PSX Doom Fire (Sanglard). Координаты: `buffer[y][x]`, y=0 — верх,
y=h-1 — источник (всегда 36). Шаг (один проход снизу вверх):

```
для y от h-1 до 1, для каждого x:
  src = buf[y][x]
  if src == 0: buf[y-1][x] = 0
  else:
    rand = randint(0, 3)
    dst  = x - rand + 1 + wind        # wind ∈ [-3..3], 0 = без ветра
    buf[y-1][dst] = max(0, src - (rand & 1))   # вне границ — пропустить
```

Палитра: 37 RGB-кортежей классической Doom-палитры (0..36).
Высота поля = rows*2 (half-block трюк), ширина = cols.

## 2. Рендер (half-block ▀)

- Кадр = ОДНА строка-буфер, ровно один `sys.stdout.write` + flush на кадр.
- Вход: `\x1b[?1049h\x1b[?25l`; выход: `\x1b[?1049l\x1b[?25h\x1b[0m`
  (ровно один раз, идемпотентно — atexit + SIGTERM + обычный выход).
- Каждая терминальная строка = пара строк поля: символ `▀`
  (`\u2580`), foreground = цвет верхней половины (`\x1b[38;2;r;g;b;m`),
  background = нижней (`\x1b[48;2;r;g;b;m`); в конце кадра `\x1b[0m`,
  начало кадра `\x1b[H`.
- **Grill (производительность):** escape-строки для всех 37×37 пар
  предвычисляются в lookup-таблицу при импорте; рендер кадра = сборка из
  кэша, без f-строк в горячем цикле.

## 3. Цикл и выживаемость (grill встроен в критерии)

- FPS-цель (default 30, аргумент CLI), delta-time компенсация.
- **Grill (resize-гонка):** SIGWINCH только ставит флаг; геометрия/буфер
  пересчитываются в начале следующего тика — никогда внутри render/step.
- **Grill (terminal hygiene):** teardown гарантирован при SIGINT, SIGTERM,
  необработанном исключении (atexit + signal handlers, идемпотентный).
- **Interactivity:** non-blocking raw-mode чтение stdin (termios/tty +
  select): стрелки ←/→ = wind, ↑/↓ = интенсивность затухания, q/Ctrl-C = quit.
  Опрос не блокирует тик.

## 4. Тикеты (порядок обязателен, каждый — зелёный полный suite)

| Ticket | Deliverables | Суть |
|---|---|---|
| CC-240 (FIRE-01) | `src/fire_engine.py` + tests | палитра+математика, чистые функции, детерминизм через seed |
| CC-241 (FIRE-02) | `src/fire_render.py` + tests | half-block рендер + кэш 37×37 + alt-buffer константы |
| CC-242 (FIRE-03) | `src/fire_main.py` + tests | цикл FPS/resize-flag/teardown (testable seams) |
| CC-243 (FIRE-04) | `src/fire_input.py`, edit `src/fire_main.py` + tests | raw-mode input → wind/intensity |
| CC-244 (FIRE-05) | `tests/fire_pty_test.py` | stdlib-pty E2E: ▀+truecolor в байтах, SIGINT→teardown, SIGWINCH→выживание |

Contract-lock: каждый последующий тикет НЕ трогает tests/ предыдущих
(protected после создания); `edit:` разрешён только для src-файлов волны.

## 5. Приёмка волны (супервайзер по evidence)

Каждый тикет: rc=0, verifier PASS, contract_lock_violations=[] (обычная
SUCCESS-приёмка — это feature, не smoke). Финал волны: полный suite зелёный,
E2E-тест доказывает корректный TTY-теardown без человека.
