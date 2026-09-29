# TASK-FIRE-13: Probe — headless determinism (temperature 0.0 verification run)

edit: src/fire/cli.py
run.sh: exists

## Задача

Проверочный прогон (probe) — новых артефактов НЕТ. Требование:
headless-детерминизм fire CLI — два вызова
`main(["--seed", "42", "--frame", "5", "--width", "20", "--height",
"10"], stream=...)` дают идентичный непустой вывод. Это УЖЕ реализовано
(TASK-FIRE-09) и покрыто существующим
`tests/fire_headless_test.py::test_frame_n_deterministic`.

Код НЕ менять. Выполни `bash scripts/run.sh test
tests/fire_headless_test.py` — если green, тикет предудовлетворён
(NO-OP): финальный отчёт без единого Write/Edit.
