# TASK-FIRE-04: Sub-pixel Half-Block Terminal Renderer

impl: src/fire/renderer.py
test: tests/renderer_test.py

## Задача
Реализовать модуль `src/fire/renderer.py` и тесты `tests/renderer_test.py`.

## Концепция
Символ `▀` (U+2580, Upper Half Block) рисует верхнюю половину знакоместа цветом Foreground (`\033[38;2;R;G;Bm`), а нижнюю — цветом Background (`\033[48;2;R;G;Bm`).
Это позволяет в терминале высотой $H$ строк отрисовывать огонь с вертикальным разрешением $2 \times H$.

## Требования
Класс `FireRenderer(palette: list[tuple[int, int, int]])`:
1. Метод `render(buffer: list[list[int]]) -> str`:
   - Принимает матрицу тепла высотой $2 \times H$ и шириной $W$.
   - Проходит парами строк: `y` (верх) и `y + 1` (низ).
   - Сопоставляет интенсивность цвета через палитру: `fg_rgb = palette[val_top]`, `bg_rgb = palette[val_bottom]`.
   - Генерирует ANSI-строку: `\033[38;2;r;g;bm\033[48;2;r;g;bm▀`.
   - Оптимизация: не слать повторный ANSI-код, если цвет предыдущего пикселя совпал с текущим.
   - В конце кадра сбрасывает цвет: `\033[0m`.

## Gate / Проверка
`pytest tests/renderer_test.py`
- Передача тестовой матрицы 4×2 возвращает 2 строки терминального вывода (каждая по 4 символа `▀`).
- Вывод содержит валидные эскейп-коды 24-bit TrueColor (`38;2;` и `48;2;`).
