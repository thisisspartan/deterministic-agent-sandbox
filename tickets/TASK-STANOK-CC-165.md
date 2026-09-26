# TASK-STANOK-CC-165: Smoke ticket — machine run (post loop-guard, second smoke)

impl: src/smoke_math.py
test: tests/smoke_math_test.py
run.sh: exists

## Задача
1. Создать `src/smoke_math.py` — модуль с двумя чистыми функциями:
   - `gcd(a, b)` — наибольший общий делитель целых чисел (итеративный
     алгоритм Евклида; `gcd(0, 0) == 0`; отрицательные аргументы
     приводятся к модулю).
   - `is_prime(n)` — проверка числа на простоту; `n < 2` → `False`;
     проверка делителей до `sqrt(n)` включительно.
2. Создать `tests/smoke_math_test.py` (pytest):
   - `gcd`: `gcd(12, 18) == 6`; `gcd(7, 13) == 1`; `gcd(0, 5) == 5`;
     `gcd(0, 0) == 0`; `gcd(-12, 18) == 6`.
   - `is_prime`: `0, 1, 2, 3, 4, 97, 100, 7919` — ожидаемые
     `False, False, True, True, False, True, False, True`.

## Gate / Проверка
`pytest tests/smoke_math_test.py`
