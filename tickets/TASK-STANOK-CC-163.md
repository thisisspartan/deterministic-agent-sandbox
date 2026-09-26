# TASK-STANOK-CC-163: Smoke ticket — machine run with loop-guard hook installed

impl: src/smoke_util.py
test: tests/smoke_util_test.py
run.sh: exists

## Задача
1. Создать `src/smoke_util.py` — модуль с двумя чистыми функциями:
   - `clamp(v, lo, hi)` — ограничивает число диапазоном `[lo, hi]`.
   - `lerp(a, b, t)` — линейная интерполяция; `t` предварительно
     ограничивается `[0, 1]` через `clamp`.
2. Создать `tests/smoke_util_test.py` (pytest):
   - `clamp`: значение внутри диапазона не меняется; ниже `lo` → `lo`;
     выше `hi` → `hi`; вырожденный случай `lo == hi` → это значение.
   - `lerp`: `t=0` → `a`; `t=1` → `b`; `t=0.5` → середина;
     `t < 0` и `t > 1` обрабатываются как 0 и 1 (clamp).

## Gate / Проверка
`pytest tests/smoke_util_test.py`
