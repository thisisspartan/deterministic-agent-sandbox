# TASK-FIRE-12: Performance budget + small-terminal polish

edit: src/fire/simulator.py
edit: src/fire/renderer.py
test: tests/fire_polish_test.py
run.sh: exists

## Задача

Закрыть бэклог реализма (CC-110 из
`specs/SPEC-STANOK-FIRE-REALISTIC-2026-09-23.md`): бюджет производительности
и устойчивость на маленьких терминалах.

Бенчмарк супервизора на хосте: 300 кадров 80x24 (advance + render) =
~1.7s. Бюджет тикета — 5s (запас ~3x). **Оптимизация горячего пути
(`step`/`render`) разрешена ТОЛЬКО если бюджет нарушается** — иначе
`src/` не трогать.

## Тесты (TDD: сначала тесты, они должны падать до фикса)

Новый `tests/fire_polish_test.py`. Существующие тесты не менять и не
удалять.

- `test_perf_300_frames_budget`:
  `app = FireApp(fps=30, seed=42, width=80, height=24,
  stream=io.StringIO())`; замерить `time.perf_counter` вокруг 300 итераций
  `app.advance(1)` + `app.current_frame()` → elapsed `< 5.0` с.
- `test_small_terminal_10x5`:
  `rc = main(["--seed", "42", "--frame", "0", "--width", "10", "--height",
  "5"], stream=buf)` → `rc == 0` и
  `buf.getvalue().count("\u2580") == 50`.
- `test_tiny_terminal_1x1`:
  `rc = main(["--seed", "42", "--frame", "0", "--width", "1", "--height",
  "1"], stream=buf)` → `rc == 0` и `count("\u2580") == 1`.
- `test_small_terminal_frames`:
  `rc = main(["--seed", "42", "--frames", "5", "--width", "10", "--height",
  "5"], stream=buf)` → `rc == 0` и `count("\u2580") == 250`.
- `test_deterministic_60_frame_run`: два `FireApp(fps=30, seed=7, width=20,
  height=10, stream=io.StringIO())`; у обоих `advance(60)` →
  `current_frame()` идентичны.

## Ограничения

- Чистый stdlib, без новых зависимостей.
- `src/fire/simulator.py` и `src/fire/renderer.py` менять только в случае
  нарушения бюджета (без изменения наблюдаемого поведения: кадры при
  том же seed остаются идентичными — все существующие тесты green).
- Не трогать `src/fire/cli.py`, `src/fire/palette.py`, `scripts/run.sh`.
- Все существующие тесты остаются green.

## Gate / Проверка

- `bash scripts/run.sh test tests/fire_polish_test.py` — green.
- `bash scripts/run.sh test --all` — green.
