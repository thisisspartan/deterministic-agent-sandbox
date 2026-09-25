# TASK-FIRE-02: Fire Simulation Engine (Heat Diffusion)

impl: src/fire/simulator.py
test: tests/simulator_test.py

## Задача
Реализовать чистый симулятор тепла в `src/fire/simulator.py` и тесты `tests/simulator_test.py`.

## Требования
Класс `FireSimulation(width: int, height: int, decay_min: int = 1, decay_max: int = 4)`:
1. Хранит буфер тепла `buffer: list[list[int]]` размером `width * height`, значения 0..255.
2. Метод `ignite_bottom(intensity_min=200, intensity_max=255)`:
   - Заполняет самую нижнюю строку случайными значениями высокой температуры (с возможностью редких пропусков/очагов).
3. Метод `step(wind: int = 0)`:
   - Пересчитывает тепло для строк от 0 до height - 2 (снизу вверх).
   - Для каждой ячейки `(x, y)` новое значение берётся из точки ниже `(x, y + 1)`:
     - Смещение по горизонтали: `dst_x = x - wind + random.choice([-1, 0, 1])`.
     - Затухание: `heat = max(0, src_heat - random.randint(decay_min, decay_max))`.
     - Запись в `buffer[y][dst_x]`.
4. Никаких зависимостей от `curses` или `sys.stdout`.

## Gate / Проверка
`pytest tests/simulator_test.py`
- Инициализация нулями.
- При вызове ignite_bottom нижняя строка нагревается (>0).
- При 10 шагах без поджига средняя температура буфера падает (охлаждение).
- Верхняя строка холоднее нижней.
