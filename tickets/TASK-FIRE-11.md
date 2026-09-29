# TASK-FIRE-11: Flicker (per-frame global intensity) + smoke particles

edit: src/fire/simulator.py
edit: src/fire/renderer.py
edit: src/fire/cli.py
test: tests/fire_smoke_flicker_test.py
run.sh: exists

## Задача

Два оставшихся эффекта реализма из
`specs/SPEC-STANOK-FIRE-REALISTIC-2026-09-23.md`:

1. **Flicker** — глобальный коэффициент интенсивности на кадр
   (последовательные кадры различаются).
2. **Дым** — редкие серые частицы, поднимающиеся над верхом пламени
   и затухающие.

Критическое ограничение: `tests/cli_test.py` (защищён, менять нельзя)
подменяет `app.sim` на `_StubSim`, у которого есть ТОЛЬКО
`update_wind`, `step`, `spawn_sparks`. Поэтому:

- эволюция и спавн дыма живут ВНУТРИ `FireSimulation.step()`
  (как уже живут embers) — `FireApp._step()` не получает новых вызовов
  к `sim`;
- flicker вычисляется в `FireApp` через СОБСТВЕННЫЙ
  `random.Random(seed)` (не через `sim._rng`).

### Изменения в `src/fire/simulator.py`

1. **`__init__`**: `self.smoke: List[List[int]]` — сетка того же размера,
   что и `buffer`, все значения `0` (0 = дыма нет, `>0` = оставшаяся
   жизнь частицы).
2. **`update_smoke()`** (public): каждая частица поднимается на 1 строку
   вверх и теряет 1 жизнь: новая сетка, `new[y-1][x] = max(new[y-1][x],
   life - 1)` для ячеек с `life > 1` и `y > 0`; частица на строке 0 или с
   `life == 1` исчезает.
3. **`spawn_smoke()`** (public): с вероятностью `0.5`
   (`self._rng.random()`) рождается одна частица: случайный столбец
   `x = self._rng.randrange(width)`; ищется верх пламени в этом
   столбце (минимальное `y`, где `buffer[y][x] > 0`); если найдено и
   `y > 0` — `smoke[y-1][x] = max(smoke[y-1][x],
   self._rng.randint(8, 16))`. Если в столбце пламени нет — частицы нет.
4. **`step()`**: в конце (после float embers) вызвать
   `self.spawn_smoke()`, затем `self.update_smoke()`. Тепло-буфер
   `step()` НЕ трогает (дым — отдельная сетка).

### Изменения в `src/fire/renderer.py`

1. Модульная константа `SMOKE_GRAY = (60, 60, 65)`.
2. **`render(buffer, flicker=1.0, smoke=None)`**: `smoke` — прямоугольная
   2D-сетка int `>= 0` того же размера, что `buffer`, или `None`.
   Валидация — `ValueError` при нарушении. Порядок на ячейку:
   flicker → jitter → выбор цвета; если `smoke[y][x] > 0` — fg ячейки =
   `SMOKE_GRAY` (вместо палитры), если `smoke[y+1][x] > 0` — bg =
   `SMOKE_GRAY`. Всё остальное (half-block, dedup кодов цвета,
   завершающий reset) без изменений.

### Изменения в `src/fire/cli.py`

1. `import random`.
2. **`FireApp.__init__`**: `self._flicker = 1.0`;
   `self._flicker_rng = random.Random(seed)` (seed может быть `None`).
3. **`_step()`**: в конце —
   `self._flicker = 1.0 + self._flicker_rng.uniform(-0.15, 0.15)`
   (диапазон `[0.85, 1.15]`). Новые вызовы к `self.sim` НЕ добавлять.
4. **`current_frame()`**:
   `self.renderer.render(self.sim.buffer, flicker=self._flicker,
   smoke=self.sim.smoke)`.
5. **`run()`**: писать `self.current_frame()` вместо прямого
   `self.renderer.render(self.sim.buffer)`.
6. Парсер аргументов, `main`, signal-обработчики,
   `enter_fullscreen`/`exit_fullscreen` — не менять.

## Тесты (TDD: сначала тесты, они должны падать до фикса)

Новый `tests/fire_smoke_flicker_test.py`. Существующие тесты не менять
и не удалять.

Flicker:
- `test_flicker_range`: `app = FireApp(fps=30, seed=7, width=20,
  height=10, stream=io.StringIO())`; 10 раз `app.advance(1)` и собрать
  `app._flicker` → все значения в `[0.85, 1.15]` и `len(set(vals)) > 1`.
- `test_flicker_deterministic`: два `FireApp` с одинаковым seed (остальное
  то же) → одинаковые последовательности `app._flicker` на 5 кадрах.
- `test_flicker_default_one`: свежий `FireApp` (без `advance`) →
  `app._flicker == 1.0`.

Дым (симулятор):
- `test_smoke_rises_and_fades`: `sim = FireSimulation(4, 8, seed=1)`;
  `sim.smoke[3][2] = 5`; 3 раза `sim.update_smoke()` →
  `sim.smoke[0][2] == 2`; ещё раз `sim.update_smoke()` → все значения
  `smoke` равны 0.
- `test_spawn_smoke_populates`: `sim = FireSimulation(20, 40, seed=5)`;
  `sim.ignite_bottom()`; 50 раз `sim.spawn_smoke()` → в `sim.smoke` есть
  значение `> 0`.
- `test_smoke_rises_over_frames`: `sim = FireSimulation(20, 40, seed=11)`;
  `sim.ignite_bottom()`; 30 раз `sim.step()`; на каждом кадре, где дым
  есть, записать минимальный `y` дыма (`tops`) → `tops` непуст и
  `min(tops) < max(tops)` (дым поднимался).

Дым (рендерер + CLI):
- `test_smoke_renders_gray`: буфер 4x4 все 0; `smoke` 4x4 все 0, кроме
  `smoke[0][0] = 5`. `FireRenderer(generate_fire_palette()).render(
  buffer, smoke=smoke)` → содержит `"\033[38;2;60;60;65m"`; без `smoke`
  → не содержит.
- `test_cli_smoke_present`:
  `main(["--seed", "42", "--frame", "30", "--width", "20", "--height",
  "10"], stream=buf)` → кадр содержит `"\033[38;2;60;60;65m"`.

## Ограничения

- Чистый stdlib, без новых зависимостей.
- `FireApp._step()` не получает новых вызовов к `self.sim` (stub в
  `tests/cli_test.py` должен остаться green без изменений).
- Не трогать `src/fire/palette.py`, `scripts/run.sh`.
- Существующие `tests/simulator_test.py`, `tests/renderer_test.py`,
  `tests/cli_test.py`, `tests/fire_determinism_test.py`,
  `tests/fire_headless_test.py`, `tests/fire_realism_test.py` остаются
  green.

## Gate / Проверка

- `bash scripts/run.sh test tests/fire_smoke_flicker_test.py` — green.
- `bash scripts/run.sh test tests/cli_test.py` — green (stub-регрессия).
- `bash scripts/run.sh test tests/fire_realism_test.py` — green (регрессия).
- `bash scripts/run.sh test --all` — green.
