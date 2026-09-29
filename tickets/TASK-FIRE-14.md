# TASK-FIRE-14: Probe — determinism regression (STANOK_TEMP 0.0 verification run)

edit: src/fire/simulator.py
run.sh: exists

## Задача

Проверочный прогон (probe) — новых артефактов НЕТ. Требование:
детерминизм симулятора по seed — существующие
`tests/fire_determinism_test.py` (same-seed идентичность,
different-seed различие, seed=None валиден) и
`tests/simulator_test.py` (регрессия) остаются green. Это УЖЕ
реализовано (TASK-FIRE-08) и покрыто этими тестами.

Код НЕ менять. Выполни:
- `bash scripts/run.sh test tests/fire_determinism_test.py`
- `bash scripts/run.sh test tests/simulator_test.py`

Если оба green, тикет предудовлетворён (NO-OP): финальный отчёт
без единого Write/Edit.
