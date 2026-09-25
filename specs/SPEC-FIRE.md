# SPEC-FIRE: Realistic Terminal Fire Simulation Engine

## 1. Цель
Создать высокопроизводительный, визуально реалистичный эмулятор огня для терминала на чистом Python (без внешних зависимостей C/curses, только stdlib), работающий с частотой 30–60 FPS.

## 2. Архитектура и модули
1. `src/fire/palette.py` — генерация TrueColor RGB-палитр (256 уровней интенсивности: Blackbody / Fire / Blue Flame).
2. `src/fire/simulator.py` — чистая матричная модель конвекции тепла (источник, затухание, вектор ветра, искры). Не зависит от терминала (100% покрытие unit-тестами).
3. `src/fire/renderer.py` — преобразование тепловой карты в строковый буфер ANSI TrueColor с использованием Half-Block `▀` (удвоение вертикального разрешения).
4. `src/fire/cli.py` — цикл событий, обработка терминальных сигналов (SIGINT, SIGWINCH), non-blocking I/O, тайминг кадров.

## 3. Требования к тестированию
- Все модули `palette`, `simulator` и `renderer` должны покрываться тестами без реального терминала (headless pytest).
- Тест рендерера проверяет корректность ANSI-эскейп последовательностей и размеры кадров.
- Тест симулятора проверяет энтропию, охлаждение к верху экрана и реакцию на ветер.

## 4. Тикеты
- TASK-FIRE-01: TrueColor Palette Generator
- TASK-FIRE-02: Fire Simulation Engine (Heat Diffusion)
- TASK-FIRE-03: Wind Turbulence & Floating Embers
- TASK-FIRE-04: Sub-pixel Half-Block Terminal Renderer
- TASK-FIRE-05: Main CLI, Terminal Controls & Signal Handling
- TASK-FIRE-06: Headless Benchmark, Smoke Test & Docs
