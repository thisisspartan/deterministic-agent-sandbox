# CLEANUP-INVENTORY (P0, CC-257, 2026-10-12)

Инвентаризация stanok-зеркала без правок. Основа: решения оператора —
продуктовые волны уходят из зеркала (P1 разрешён), старый Docker-путь удаляем
(P3 разрешён). Остальные фазы — по отдельному одобрению (инфраструктура
заморожена).

## Эталон (зафиксирован до любых правок)

- Stanok HEAD `695c860`, parent `d098a47`.
- Харнесс: `.venv/bin/python -m pytest launcher/tests_harness -q` →
  **505 passed / 0 skipped** (37.6s; docker/jq/kubectl доступны на хосте
  супервизора). Прежняя цифра 503/2 — те же тесты при недоступных инструментах
  (skip-гарды); эталоном считается текущий замер на этом хосте.
- Protected (не трогать вне P5): `scripts/run.sh`, `scripts/stacks/*.toml`,
  `Dockerfile`, `image-requirements.lock`, `test_verdict_safety.py`,
  `test_verdict_table.py`.
- DIGEST_INPUTS (изменение = пересборка + новый пин): Dockerfile,
  scripts/run.sh, scripts/stacks/*.toml, image-requirements.lock.

## P1-кандидаты: продуктовые волны (ОДОБРЕНО оператором)

Референс-проверка: имена продуктовых модулей встречаются ТОЛЬКО в самих
продуктовых файлах (grep по всему дереву — 17 файлов, все продуктовые;
launcher/, tests_harness/, scripts/, ARCHITECTURE.md, README.md, CLAUDE.md —
ноль ссылок). Удаление безопасно для харнесса и DIGEST_INPUTS.

- `src/`: csv_stats.py, text_stats.py, fire_engine.py, fire_render.py,
  fire_main.py, fire_input.py (6)
- `tests/`: csv_stats_test.py, text_stats_test.py, fire_engine_test.py,
  fire_input_test.py, fire_main_test.py, fire_render_test.py, fire_pty_test.py (7)
- `docs/`: csv_stats.md, text_stats.md, fire_engine.md, fire_render.md,
  fire_main.md, fire_input.md (6)
- `.gitkeep` в src/tests/docs — ОСТАВИТЬ (каталоги после удаления пусты;
  машина создаёт артефакты тикетов в этих зонах).
- Содержание сохраняется в истории: parent-пины darkcast (67e5635, 95e50be,
  55effb2..a1dd1d4) и история origin+github; без переписывания истории.

## P3-кандидаты: старый Docker-путь (ОДОБРЕНО оператором)

bwrap/unconfined: 49 вхождений в 17 файлах + `sandbox`-блок в
`.claude/settings.stanok.json` (стр. 52, без bwrap-строк):
launcher/sandbox.py (11), launcher/tests_harness/test_tmp_bind.py (9),
launcher/pod_runner.py (3), launcher/cli.py (3), launcher/tests_harness/
test_k8s_pod_settings.py (3), Dockerfile (4), launcher/tests_harness/
test_stage3_fresh_verify.py (5), launcher/k8s.py (2), launch.sh, gates.py,
verify.py, test_sandbox_config_gate.py, test_k8s_manifests.py,
test_k8s_wiring.py, test_scenarios_verdict.py, k8s/worker-job.yaml.tmpl,
k8s/networkpolicy.yaml.tmpl.
Замечание: часть вхождений в k8s-файлах — комментарии/наследие строк, не
Docker-ветка; разбор пофайловый нужен в P3, не механическое удаление.
Связано с RA-3 (удаление Docker-fallback запланировано на 2026-12-01 — P3
досрочно по решению оператора).

## P4-кандидаты: мёртвый код (требует отдельного одобрения)

- `requirements.txt` — НЕ мёртвый: setup.sh:22 ставит из него зависимости. Сохранить.
- `specs/.gitkeep`, `tickets/.gitkeep` в stanok — ссылок в launch.sh/cli.py не
  найдено; кандидат на удаление (проверить sandbox-монтирования перед удалением).
- Прочий мёртвый код: простой подсчёт ссылок кандидатов не дал; нужен анализ
  графа импортов (отложен).

## P5: входы образа (bubblewrap в Dockerfile)

Dockerfile содержит 4 bwrap-ссылки; удаление меняет DIGEST_INPUTS →
пересборка, пуш, новый пин. Только вместе с гейтом doctor + smoke на новом
образе. Отложено до одобрения.

## Вне списка (осознанно сохранено)

- `infra/netpol-smoke.sh`, `k8s/*`, `launcher/*`, `hooks/doctor.sh`,
  `.claude/hooks/loop-guard.py` — инфраструктура зеркала.
- `docs/gvisor-trial.md` — в main checkout ОТСУТСТВУЕТ (жил в worktree
  cc253, удалён с ним) — ничего удалять не нужно.
