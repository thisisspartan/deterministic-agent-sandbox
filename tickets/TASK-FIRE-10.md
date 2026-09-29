# TASK-FIRE-10: Renderer realism — blue combustion base + anti-banding jitter

edit: src/fire/renderer.py
edit: src/fire/cli.py
test: tests/fire_realism_test.py
run.sh: exists

## Задача

Добавить в рендерер два эффекта реализма из
`specs/SPEC-STANOK-FIRE-REALISTIC-2026-09-23.md`:

1. **Синий конус сгорания** — нижние строки буфера (топливная линия)
   рисуются по синей (газовой) палитре, как у реального пламени.
2. **Анти-бэндинг** — детерминированный per-cell jitter значений тепла,
   чтобы плоские области не давали жёсткие цветовые ступеньки.

Плюс параметр `flicker` в `render()` (сейчас только контракт,
подключение по кадрам — в TASK-FIRE-11).

### Изменения в `src/fire/renderer.py`

1. **`FireRenderer.__init__(palette, blue_palette=None, base_rows=0,
   jitter_seed=None)`** — существующий параметр `palette` и его
   валидация не менять; добавить:
   - `blue_palette` — палитра 256 записей `(r, g, b)` или `None`.
     Валидация та же, что для `palette` (непустой список кортежей int
     `[0..255]`).
   - `base_rows` — int `>= 0`: количество НИЖНИХ строк буфера (считая
     от последней), которые индексируются в `blue_palette` вместо
     `palette`. `0` или `blue_palette=None` → эффект выключен.
   - `jitter_seed` — int или `None`. Если не `None` — анти-бэндинг
     включён.
2. **`render(buffer, flicker=1.0)`** — порядок преобразований значения
   ячейки перед выбором цвета:
   1. `flicker` (float `> 0`): `value = clamp(round(value * flicker), 0, 255)`;
      `1.0` → no-op (дефолт);
   2. jitter: если `jitter_seed is not None` — к значению прибавляется
      `{-1, 0, 1}`, результат clamp в `[0, 255]`. Детерминизм: на каждый
      вызов `render()` создаётся свежий `random.Random(jitter_seed)`,
      значения потребляются в порядке обхода буфера (строки сверху вниз,
      в строке слева направо) — одинаковый буфер → одинаковый кадр.
   3. выбор палитры: строка буфера `y` (и `y+1` для bg) берётся из
      `blue_palette`, если `y >= height - base_rows`, иначе из `palette`.
   Всё остальное (half-block `▀`, эмиссия кода цвета только при смене,
   завершающий `\033[0m`, валидация буфера) — без изменений.
3. Валидация: `base_rows` не int или `< 0` → `ValueError`;
   `flicker` не число или `<= 0` → `ValueError`.

### Изменения в `src/fire/cli.py`

1. Модульная константа `BASE_ROWS = 4` (строки буфера = 2 строки
   терминала).
2. В `handle_resize()` рендерер создаётся с синим основанием и jitter:
   ```python
   self.renderer = FireRenderer(
       palette,
       blue_palette=generate_blue_fire_palette(),
       base_rows=BASE_ROWS,
       jitter_seed=self.seed,
   )
   ```
   (`generate_blue_fire_palette` уже импортирован в `cli.py`.)
3. Ничего больше не менять: `main`, `run`, `_step`, signal-обработчики,
   `enter_fullscreen`/`exit_fullscreen`, парсер аргументов.

## Тесты (TDD: сначала тесты, они должны падать до фикса)

Новый `tests/fire_realism_test.py`. Существующие тесты не менять и не
удалять. Хелпер: `_BLUE = [(0, 0, 0)] * 128 + [(0, 0, 255)] * 128`
(256 записей, «явно синий» горячий диапазон).

- `test_blue_base_used`: буфер 4 строки x 4 столбца, строки 0..1 = 0,
  строки 2..3 = 200.
  `FireRenderer(generate_fire_palette(), blue_palette=_BLUE,
  base_rows=2).render(buffer)` → содержит `"\033[38;2;0;0;255m"`
  (fg строки 2 по синей палитре).
- `test_no_blue_base_without_palette`: тот же буфер,
  `FireRenderer(generate_fire_palette()).render(buffer)` → НЕ содержит
  `"\033[38;2;0;0;255m"`.
- `test_jitter_breaks_banding`: плоский буфер 4x4, все значения 128.
  `FireRenderer(generate_fire_palette(), jitter_seed=7).render(buffer)`
  → число различных fg-кодов (`\033[38;2;...m`) > 1; без jitter
  (`FireRenderer(generate_fire_palette())`) → ровно 1.
- `test_jitter_deterministic`: тот же плоский буфер, два вызова
  `render` с `jitter_seed=7` → идентичные строки.
- `test_flicker_default_noop`: для любого буфера
  `render(buffer) == render(buffer, flicker=1.0)`.
- `test_flicker_scales`: буфер 2x2, одна ячейка 128, остальные 0.
  `flicker=2.0` → fg горячей ячейки = `palette[255]` (clamp);
  `flicker=0.5` → `palette[64]`.
- `test_cli_wires_blue_base`:
  `main(["--seed", "42", "--frame", "5", "--width", "20", "--height",
  "10"], stream=buf)` → в кадре есть SGR-цвет `(r, g, b)` с
  `b - r >= 50` (синее доминирование — признак синего основания;
  в огненной палитре максимум `b - r` = 35).

## Ограничения

- Чистый stdlib, без новых зависимостей.
- Не трогать `src/fire/simulator.py`, `src/fire/palette.py`,
  `scripts/run.sh`.
- Существующие `tests/renderer_test.py`, `tests/cli_test.py`,
  `tests/simulator_test.py`, `tests/fire_headless_test.py` остаются
  green (новые параметры — только с no-op дефолтами).

## Gate / Проверка

- `bash scripts/run.sh test tests/fire_realism_test.py` — green.
- `bash scripts/run.sh test tests/renderer_test.py` — green (регрессия).
- `bash scripts/run.sh test tests/fire_headless_test.py` — green (регрессия).
- `bash scripts/run.sh test --all` — green.
