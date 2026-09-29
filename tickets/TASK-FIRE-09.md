# TASK-FIRE-09: CLI flags, headless main guard, entry point

edit: src/fire/cli.py
impl: src/fire/__main__.py
test: tests/fire_headless_test.py
run.sh: exists

## Задача

Сделать fire-приложение детерминированно тестируемым headless и дать ему
entry point. Сейчас `src/fire/cli.py` не имеет ни `main()`, ни
`if __name__ == "__main__"`, ни `src/fire/__main__.py` — `FireApp.run()`
нигде не вызывается, а флаги только `--fps/--palette/--wind`. Симулятор
уже детерминирован по seed (TASK-FIRE-08: `FireSimulation(..., seed=...)`).

### Изменения в `src/fire/cli.py`

1. **Новые флаги** в `build_parser()` (существующие `--fps/--palette/
   --wind` не менять):
   - `--seed N` (int, default `None`) — seed PRNG симулятора.
   - `--width W` (int, default `None`) — переопределить ширину терминала.
   - `--height H` (int, default `None`) — переопределить высоту терминала.
   - `--frames N` (int ≥ 0, default `None`) — отрендерить N кадров и
     завершиться с кодом 0.
   - `--frame N` (int ≥ 0, default `None`) — отрендерить ровно кадр N и
     завершиться с кодом 0.
   - `--frame` и `--frames` — взаимоисключающие (mutually exclusive).
   - `--width`/`--height` ≥ 1.
2. **`FireApp.__init__`** — добавить параметры `seed=None`, `width=None`,
   `height=None` (ПОСЛЕ `stream`, с дефолтами). Сохранить их до вызова
   `handle_resize()`. `handle_resize()` использует `width`/`height`
   (когда не `None`) вместо `get_terminal_size()`, и передаёт `seed` в
   `FireSimulation(width=..., height=2*height, seed=...)`.
3. **Методы для headless-рендера** (имена на усмотрение, контракт ниже):
   - advance на N кадров (N вызовов `_step()`);
   - вернуть текущий отрендеренный кадр строкой
     (`self.renderer.render(self.sim.buffer)`).
4. **Функция `main(argv=None, stream=None) -> int`**:
   - парсит `argv` (default `sys.argv[1:]`) через `build_parser()`;
   - создаёт `FireApp(fps, palette_name, wind, stream, seed, width, height)`;
   - если задан `--frame N`: advance(N), записать `current_frame()` в
     `stream`, вернуть 0;
   - иначе если задан `--frames N`: N раз (кадр 0, 1, ..., N-1) записать
     `current_frame()` + `\n`, затем advance(1); вернуть 0;
   - иначе если НЕ TTY (`sys.stdin.isatty()` False): записать один кадр
     (кадр 0) в `stream`, вернуть 0;
   - иначе (TTY, интерактив): `app.run()`, вернуть 0.
   - `--frame`/`--frames` имеют приоритет над TTY-проверкой.
5. **`if __name__ == "__main__": sys.exit(main())`** в конце `cli.py`.

### Новый `src/fire/__main__.py`

Позволяет `python3 -m fire`:
```python
import sys
from fire.cli import main

sys.exit(main())
```

## Тесты (TDD: сначала тесты, они должны падать до фикса)

Новый `tests/fire_headless_test.py`. Тесты вызывают `fire.cli.main(argv,
stream=buf)` in-process (`buf = io.StringIO()`), без subprocess.
Существующие тесты не менять и не удалять.

- `test_frame_n_deterministic`: два вызова
  `main(["--seed","42","--frame","5","--width","20","--height","10"],
  stream=...)` → идентичный, непустой вывод.
- `test_seed_changes_frame`: `--seed 42` vs `--seed 43` (остальное то же,
  `--frame 5 --width 20 --height 10`) → вывод РАЗЛИЧЕН.
- `test_frames_n_exits_zero`: `rc = main(["--seed","42","--frames","3",
  "--width","20","--height","10"], stream=buf)` → `rc == 0` и
  `buf.getvalue().count("\u2580") == 3 * 20 * 10` (3 кадра по W*H
  half-block'ов).
- `test_headless_one_frame`: `rc = main(["--seed","42","--width","20",
  "--height","10"], stream=buf)` (без `--frame`/`--frames`; pytest без
  TTY → headless-ветка) → `rc == 0` и
  `buf.getvalue().count("\u2580") == 20 * 10` (один кадр).
- `test_width_height_respected`: `--frame 0 --width 20 --height 10` →
  `count("\u2580") == 200`; `--frame 0 --width 20 --height 20` →
  `count("\u2580") == 400` (разные высоты → разные кадры).

## Ограничения

- Чистый stdlib, без новых зависимостей.
- Не менять поведение `_step()`, `run()`, signal-обработчиков,
  `enter_fullscreen`/`exit_fullscreen`.
- Не трогать `src/fire/simulator.py`, `src/fire/palette.py`,
  `src/fire/renderer.py`, `scripts/run.sh`.
- Существующие `tests/cli_test.py` и `tests/simulator_test.py` должны
  остаться green (сигнатура `FireApp.__init__` расширяется только
  дефолтными параметрами).

## Gate / Проверка

- `bash scripts/run.sh test tests/fire_headless_test.py` — green.
- `bash scripts/run.sh test tests/cli_test.py` — green (регрессия).
- `bash scripts/run.sh test --all` — green.
- `python3 -m fire --seed 42 --frame 0 --width 20 --height 10` завершается
  с кодом 0 и печатает один кадр (headless).
