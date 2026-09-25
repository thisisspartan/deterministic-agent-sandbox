# TASK-FIRE-06: Headless Benchmark, Smoke Test & Docs

test: tests/smoke_test.py
docs: docs/fire.md

## Задача
1. Создать headless smoke-тест `tests/smoke_test.py`, прогоняющий 100 кадров симуляции и рендера без вывода в TTY, замеряющий чистый FPS.
2. Создать документацию `docs/fire.md`.

## Требования
1. `tests/smoke_test.py`:
   - Разрешение 120x80 (виртуальное 120x40).
   - Прогон 100 циклов (ignite -> step -> render).
   - Падение теста, если среднее время кадра > 33мс (< 30 FPS).
2. `docs/fire.md`:
   - Описание архитектуры, физической модели, формулы полублоков и палитры.
   - Инструкция по запуску: `python3 src/main.py --fps 45`.

## Gate / Проверка
`pytest tests/smoke_test.py`
`test -f docs/fire.md`
