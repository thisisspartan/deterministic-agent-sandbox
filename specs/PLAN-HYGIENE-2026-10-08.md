# PLAN-HYGIENE-2026-10-08: разбор stanok.py (2381 строки) — план, ничего не изменено

Проверено по текущему HEAD (`7a3dda8`). Все правки — operator-side (`launcher/` вне машинной зоны).
Порядок шагов в конце. Сначала — сверка каждого пункта с кодом.

## Сверка пунктов ревью

| # | Утверждение | Вердикт проверки |
|---|---|---|
| 1 | Один файл ~2237 строк | **Подтверждено** (2381). Разбиение — последний шаг. |
| 2 | ~15 rc-кодов, повторяющийся `log → early_abort` | **Подтверждено**: `early_abort` (stanok.py:2252) + ~10 вызовов с литеральными кодами. `ExitCode` enum — согласен. |
| 3 | `c5` дублирует `review_verdict` | **Частично**: при NO-OP они расходятся (c5=PASS, review_verdict=NOOP, stanok.py:1761-1763). Но ни один потребитель (e2e.sh, supervisor-протокол) их не читает — читаются `rc`, `verifier`, `probe_result`, `contract_lock_violations`. Удаление возможно, но это смена strict-контракта summary → отдельный шаг с правкой тестов. |
| 4 | Два механизма защиты тестов избыточны | **Не подтверждено — предпосылка неверна.** `host_ro_paths` (stanok.py:685-712) биндит каждый protected-файл `:ro` поверх rw-carve-out каталога `tests/` — сам каталог остаётся записываемым (машина обязана добавлять новые тесты). Удаление protected-файла = запись в родительский каталог = разрешена монтированием. Поэтому post-turn diff (вторая эшелонь, CC-137) ловит то, что mount ловить не может. Два слоя — осознанный дизайн с историей инцидентов. Оставить оба. |
| 5 | Мёртвая ветка `rc==2` + `_run_one_test` | **Подтверждено как достижимость только со старым entrypoint** (stanok.py:979-988, docstring 952-954). Но ветка не «мёртвая»: она срабатывает, если machine-bootstrapped `run.sh` не реализует `test --all`. Удаление — сознательное ужесточение (несоответствующий entrypoint → общий FAIL вместо тихого фолбэка). Допустимо, но это изменение поведения, не чистка. |
| 6 | Двойная работа с `/tmp/claude-$uid` | **Подтверждено частично**: host-путь нужен `no_sandbox`-режиму (`STANOK_NO_SANDBOX`, stanok.py:2330, 2340) — это поддерживаемый escape-hatch, не мёртвый путь. Оставить; максимум — уточнить комментарий. |
| 7 | Opik-телеметрия в основном пути | **Подтверждено**: не влияет на вердикт. Низкий приоритет: вынести в `opik.py` при разбиении (шаг 5), не раньше. |
| 8 | `test_config_gate` выглядит как тест | **Подтверждено** (stanok.py:385). Переименовать в `check_test_config` (вызов: stanok.py:2315 + обращения в tests_harness). |
| 9 | CC-ссылки в комментариях бесполезны | **Не подтверждено для darkcast**: записи CC живут в `specs/ARCHIVE/` и `specs/SPEC-*.md`; плюс протокол супervisorа требует цитирование инцидента на каждый механизм. Оставить в darkcast; убирать только в публичном skeleton. |
| 10 | `_extract_smart_diff` не извлекает | **Подтверждено** (stanok.py:885). Переименование в `_tail_output` — согласен. |
| 11 | Три источника правды в документации | **Согласен как направление.** Правило → один файл-владелец, остальные ссылаются. Объединить с B2/B3 из PLAN-AUDIT. |
| 12 | 128000 vs 123000 | **Уточнено**: 128000 — fallback при unset `STANOK_REQUIRED_WINDOW` (stanok.py:491); settings задаёт 123000. Фолбэк рассинхронизирован с реальной конфигурацией → привести к одному значению или fail-closed. |

## Поправки к прошлому ревью (важно для порядка)

- `STANOK_TEMP`, `STANOK_PROXY` — НЕ мёртвые (cli.js T-patch; P0-launch.sh:84-85 → http_proxy). Не удалять.
- `cmd_wait` rc=0 при FAIL — сознательный контракт (docstring stanok.py:2031-2033; e2e.sh Gate 2 явно на него опирается; test_wait_follow это тестирует). Ничего не ломается: вердикт читается из summary.json. Рекомендация: не менять; зафиксировать в README.
- `git_mode` — подтверждён мёртвым (задаётся stanok.py:1911, читается только тестами). Удалять.
- `e2e.sh` уже исправлен; остался устаревший `.claude/commands/e2e.md`.

## Порядок работ (каждый шаг — зелёные тесты под непривилегированным пользователем)

### Шаг 1. Целостность вердикта (из PLAN-AUDIT B1)
`scripts/stacks/*.toml` в `_protected_files()` (stanok.py:1079). Spec теста (принят от оператора, 2026-10-08):
- Ticket с объявленным `impl: scripts/probe.sh` (это делает `scripts/` RW-зоной рана).
- В ране machine пишет в `scripts/stacks/py.toml` `test_runner = "true"`.
- Ожидание: `contract_lock_violations` содержит `MODIFIED: scripts/stacks/py.toml`, rc=1.
- До фикса тест обязан падать (лаунчер сейчас не замечает правку) — red-first, как обычный тикет.
- Anti-false-positive: обычная правка `src/` и НОВЫЙ файл в `scripts/stacks/` (объявленный тикетом) — violation нет.
Попутно (не в контракте, лог): устаревшая log-строка stanok.py:600 («sha256(Dockerfile+run.sh)» — дайджест включает stacks).

### Шаг 2. Docs-правки (PLAN-AUDIT B2, B3, B5)
`.claude/commands/e2e.md` → `--follow`; комментарии Dockerfile:50,94,134 → doctor.
Дефолт Opik — менять в ОДНОМ решении обе точки: `STANOK_OPIK_URL` fallback (stanok.py:627) И
`BETA_TRACING_ENDPOINT` (settings.stanok.json:23 = `http://localhost:8080/v1/private/otel`).
Замечание: OTel-путь на :8080 означает, что в реальной деплой-цепочке Opik живёт на 8080, а llama-server
сдвинут env'ом — карта портов решается оператором по деплою, не кодом.
`cmd_wait` rc=0 при FAIL: решение принято — зафиксировать в README как текущее поведение, без изменения
(test_wait_follow тестирует эту семантику).

### Шаг 3. Мёртвый код
`git_mode` (поле + правки в test_session_plan.py / test_ro_protected_files.py); фолбэк `rc==2` + `_run_one_test`
(ужесточение контракта: требует явного решения + записи в машинный `CLAUDE.md`, что `test --all` обязателен);
`STANOK_REQUIRED_WINDOW` unset → **fail-closed** (launch отказывает), а не фолбэк 128000 (stanok.py:491) —
иначе запуск вне `P0-launch.sh` проверяет окно с чужим значением.

### Шаг 4. Переименования и enum
`test_config_gate` → `check_test_config`; `_extract_smart_diff` → `_tail_output`; `ExitCode` enum + единый `abort(code, msg)` вместо литеральных rc в main().

### Шаг 5. Разбиение модулей (последним, на зелёных тестах)
`cli.py / gates.py / ticket.py / session.py / verify.py / summary.py` (+ `opik.py` — телеметрия out of main path). Эквивалентность проверяется существующим tests_harness; поведение не меняется.
Осторожность (замечание оператора): `test_session_plan.py:91` содержит НЕГАТИВНЫЙ assert
`assert not hasattr(stanok, "_pretooluse_lock_hook")` — после разбиения он станет vacuously true
(проверит пустоту). Переписать под целевой модуль или удалить вместе с удалённым хуком.

### Шаг 6. Slim summary-контракт (решение после обсуждения)
Удалить `c5`/`review_verdict` (не consumed) или оставить как диагностику. Меняет strict-контракт summary.json → трогает tests_harness и документацию. Делать только после шага 5.

Consumer-map (grep по всему darkcast, 2026-10-08; повторный grep по значениям `"c5"`/`"review_verdict"`
и динамическим чтениям `summary.get(`/`summary[` — вне producer'а stanok.py ноль, включая tests_harness):
- `rc`, `verifier`: `.claude/e2e.sh` (branch), supervisor-протокол (branch).
- `probe_result`: supervisor-протокол (branch: NO-OP-PASS/LOOP-TRAP), `.claude/e2e.sh` (print-only), tests_harness (asserted: test_verdict_safety, test_loop_trap, test_loop_guard, test_wait_follow и др.).
- `c5`, `review_verdict`: **ноль потребителей** — ни в коде (единственный producer: stanok.py:226-227, 1751-1763, 1792-1793), ни в tests_harness (grep пуст), ни в e2e.sh. Упоминания только в docs/ARCHIVE.
→ Удаление `c5`/`review_verdict` не ломает ни один тест; трогает только docstring strict-contract (stanok.py:6) и docs. `probe_result` — сохранить (consumed).
Открытый вопрос оператору (grep его не находит): есть ли внешние читатели summary.json вне репозитория
(скрипты на других машинах, Opik-дашборды)? Если да — смена публичного JSON-контракта требует их согласия.

### Шаг 7. Единый источник правил в документации
Правило → файл-владелец; README/CLAUDE.md/run.sh-заголовок ссылается. Совместно с PLAN-AUDIT D (skeleton-pub).

## Не трогать (согласен с ревью)
setup.sh (SHA-256 CLI + patch-анкера), doctor image digest, loop-guard.py, hidden_files_gate, sandbox_config_gate, два эшелона contract lock (см. поправку к п.4).
