# TASK-FIRE-05: Main CLI, Terminal Controls & Signal Handling

impl: src/fire/cli.py
impl: src/main.py

## Задача
Создать точку входа `src/fire/cli.py` и скрипт запуска `src/main.py`.

## Требования
1. CLI аргументы (через `argparse`):
   - `--fps`: целевой FPS (по умолчанию 30, макс 60).
   - `--palette`: `fire` или `blue` (дефолт `fire`).
   - `--wind`: статичный ветер (-3..3) или `auto` (дефолт `auto`).
2. Управление терминалом (Raw ANSI, без сторонних либ):
   - Вход: переход в alternate screen (`\033[?1049h`), скрытие курсора (`\033[?25l`).
   - Выход (по `Ctrl+C` или `q`): возврат нормального экрана (`\033[?1049l`), показ курсора (`\033[?25h`), сброс цвета (`\033[0m`).
3. Динамический ресайз (`signal.SIGWINCH`):
   - При изменении размера окна терминала пересоздавать симулятор и буфер под новый размер (`shutil.get_terminal_size()`).
4. Точный тайминг кадров:
   - `time.perf_counter()` для сна: `time.sleep(max(0, frame_time - elapsed))`.

## Gate / Проверка
`python3 -m py_compile src/fire/cli.py src/main.py`
`python3 src/main.py --help` (проверка парсинга всех флагов).
