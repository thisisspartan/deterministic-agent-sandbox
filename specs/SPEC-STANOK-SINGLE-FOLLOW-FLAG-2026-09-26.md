# SPEC-STANOK-SINGLE-FOLLOW-FLAG — один фоновый флаг `--follow` (BL-1 / P.1)

Дата: 2026-09-26. Статус: согласован с оператором (дизайн-обсуждение 2026-09-26).
Закрывает: BL-1 (вариант (б) из диагностики 2026-09-26).

## Контекст

`run` имеет два фоновых флага: `--background` (detach, возврат сразу) и
`--follow` (detach + блок до терминального состояния, имплицирует
`--background`). Форма `--background` без `--follow` — единственный
не-нативный остаток: SMOKE-02-инцидент (запуск без wait-задачи → уведомление
никогда не пришло) достижим в один флаг. Нативный механизм CC
(`run_in_background: true` + автоуведомление) покрывает ожидание; единственное
не-нативное в `--follow` — 45-мин hang-cap (rc=124) и rc=17 launch-failure
distinction, которые остаются.

## Решение (вариант (б))

Один флаг: `--follow` — единственный фоновый путь. `--background` выкинут
полностью (аргумент, ветки, документация). Фоновый запуск ВСЕГДА блокирует до
терминального состояния. `wait`-сабкоманда и foreground sync-путь (без флага)
остаются без изменений.

## Изменения

1. `launcher/stanok.py`:
   - убрать `r.add_argument("--background", ...)`; комментарий `--follow`:
     единственный фоновый флаг (detach + блок в `cmd_wait` до терминального
     состояния, печать финального статуса);
   - `main()`: `if args.background or args.follow:` → `if args.follow:`;
   - `launch_background()`: обе `if args.follow ... else 0` ветки → безусловный
     `return cmd_wait(args.label)`;
   - docstring `cmd_wait`: `run --background --follow` → `run --follow`.
2. `launcher/tests_harness/test_wait_follow.py`:
   - docstring: заголовок и пункт 6 — `run --follow` (единственный фоновый флаг);
   - тест 6: комментарий «(WITHOUT --background)» → «(the sole background flag)»;
   - тест 7: убрать `background=True` из SimpleNamespace; assertion — только
     `--follow` не утекает в child argv.
3. `launch.sh` usage-строка: `[--background] [--follow]` → `[--follow]`.
4. `README.md`: usage-строка, комментарий про nonexistent ticket, буллеты
   `--background`/`--follow` (один буллет), строка :114 (`--follow` spawns a
   detached self-run and blocks until terminal).
5. `CLAUDE.supervisor.md` §3/§6: канонический вызов `run ... --follow`;
   Forbidden: фоновый запуск без `--follow` недостижим — формулировка
   «единственный фоновый флаг — `--follow`».

Не меняется: `wait`-сабкоманда (`cmd_wait`, `WAIT_TIMEOUT_S=2700`, rc=124),
foreground sync-путь, rc=17 (child died before marker), label-guard
(`run <ticket> -- --background` → label → rc=15 — это label, не флаг;
`test_doctor.py::test_runner_label_guard` остаётся).

## Acceptance criteria

1. `python launcher/stanok.py run --help` — флага `--background` нет, `--follow` есть.
2. `run <ticket> <label> --follow` идёт в `launch_background` и блокирует в
   `cmd_wait` (тест 6 test_wait_follow.py).
3. `--follow` не утекает в child argv (тест 7).
4. Полный doctor-сьют зелёный (177 passed, 2 skipped — без изменения числа тестов).
5. В `stanok/` (launcher/, launch.sh, README.md) и `CLAUDE.supervisor.md` нет
   рабочих ссылок на `--background` как на флаг (исторические упоминания
   SMOKE-02 и label-guard — не в счёт).
