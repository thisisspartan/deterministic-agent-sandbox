# TASK-FIRE-07: Fire bug fixes — ember sticking, spawn_sparks in CLI, orphan doc

edit: src/fire/simulator.py
edit: src/fire/cli.py
edit: tests/simulator_test.py
test: tests/cli_test.py
run.sh: exists

## Задача

Три бага проекта fire:

1. **Залипание углей на row 0** (`src/fire/simulator.py`, метод `step()`).
   Сейчас угли, вылетевшие за верхнюю границу (`new_y < 0`), клампятся в
   row 0 и остаются в `self._embers` навсегда, каждый тик повторно
   подогревая row 0. Исправление: уголь с `new_y < 0` должен УДАЛЯТЬСЯ
   (не добавляться в `floated`). Уголь, приземлившийся ровно в row 0,
   живёт этот тик и удаляется следующим.
2. **`spawn_sparks` не вызывается в CLI** (`src/fire/cli.py`, метод
   `FireApp._step()`). Фича углей мертва: `_step()` вызывает только
   `update_wind()`/`step()`. Исправление: в `_step()` каждый кадр
   вызывать `self.sim.spawn_sparks()` — и в ветке auto-wind, и в ветке
   статического ветра.
3. **Сиротский документ `docs/wordfreq.md`** — уже удалён супервизором до
   запуска (в манифесте нет директивы `delete:`, а `docs/` смонтирован
   `:ro` в контейнере). Файла не должно существовать — только проверить.

## Тесты (TDD: сначала тесты, они должны падать до фикса)

Расширить `tests/simulator_test.py` — ТОЛЬКО добавлять новые тесты,
существующие тесты не менять и не удалять:

- `test_ember_removed_when_above_top`: симуляция 20x10,
  `sim._embers = [(5, 1, 255)]`, один `sim.step()` → `sim._embers == []`.
- `test_ember_lands_on_row0_then_removed`: `sim._embers = [(5, 2, 255)]`;
  после первого `step()` в `sim._embers` есть `(5, 0, 255)` и
  `sim.buffer[0][5] == 255`; после второго `step()` — `sim._embers == []`.
- `test_all_embers_exit_from_top`: `sim.spawn_sparks(count=5)`, затем 10
  `sim.step()` → `sim._embers == []` (угли стартуют в rows height-2/height-3
  и поднимаются по 2 строки за тик — все вылетают за 10 тиков).

Новый `tests/cli_test.py`:

- `FireApp(fps=30, stream=io.StringIO())` конструируется headless
  (без TTY).
- Заменить `app.sim` на stub-объект, фиксирующий вызовы `update_wind()`,
  `step(wind=None)`, `spawn_sparks(count=3)`; вызвать `app._step()`:
  - auto-wind: `spawn_sparks` вызван ровно 1 раз, `update_wind` — 1 раз,
    `step` — 1 раз без аргумента wind;
  - статический ветер (`app.wind = 1`): `spawn_sparks` — 1 раз, `step`
    вызван с `wind=1`.

## Ограничения

- Не менять поведение `spawn_sparks`, `update_wind`, `ignite_bottom` и
  основного распространения тепла.
- Не трогать `scripts/run.sh`, `src/fire/palette.py`, `src/fire/renderer.py`.
- Чистый stdlib, без новых зависимостей.

## Gate / Проверка

- `bash scripts/run.sh test tests/simulator_test.py` — green.
- `bash scripts/run.sh test tests/cli_test.py` — green.
- `bash scripts/run.sh test --all` — green.
- `test ! -f docs/wordfreq.md`.
