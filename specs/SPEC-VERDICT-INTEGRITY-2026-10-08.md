# SPEC-VERDICT-INTEGRITY-2026-10-08 — целостность вердикта: fresh-check + post-turn verdict-config gate

Статус: принята оператором (пункты 1–5 + дополнения 2026-10-09: contract→FAIL, ban на
симлинки, `docker cp` обязателен для A и B, red-фаза = cc215). Диагностика (a)/(b)/(c)
выполнена до реализации. Реализация — тикет TASK-STANOK-CC-217 (машина, red-тесты первыми; условия оператора 1–7
включены в тикет; `launcher/` декларируется через edit:/impl: — declared_carveout это
разрешает). Приёмка после CC-217: повторный прогон `tickets/TASK-STANOK-CC-215.md`
(ожидание CONTRACT-FAIL) + повторный прогон тикетов CC-210/CC-211 (ожидание PASS —
regression happy-path и retry-путь).

## 0. Цель и модель угроз

Финальный вердикт (`rc`/`verifier`/`probe_result` в summary.json) должен вычисляться
независимо от self-report работника и от файлов, созданных работником mid-run и способных
подменить вердикт раннера. Угрозы:

- **T1 — mid-run verdict-config под tests/ (ДОКАЗАНА живьем, cc215-diag).**
  Машина создала `tests/conftest.py` → symlink на `tests/fixtures/conftest.py` с
  `pytest_sessionfinish: session.exitstatus = 0`; suite с `assert False` получила rc=0.
  Дыра состоит из трёх звеньев: launch-гейт rc=27 (`gates.check_test_config`, gates.py:158)
  отработал ДО создания файла; W12 (`run.sh unclaimed_files`, `find tests -type f`) не
  перечисляет symlink-файлы и освобождает `fixtures/`; машина сама нашла лазейку из текста
  fix-prompt («move it to tests/fixtures/»). Host-репродукция: `list` rc=0, `test --all` rc=0
  при падающем тесте.
- **T2 — запись работника в log-каталог (ЗАВИСИТ ОТ ВАРИАНТА барьера).**
  `sandbox.py:66` монтирует `log_dir` rw (утверждение «не смонтирован» — снято, оператор прав).
  Диагностика cc216-probe: под вариантом A (вложенный bwrap) модель видит **пустой tmpfs**
  вместо log-каталога (`ls` пуст при непустом host-каталоге); `echo probe > .../probe.txt`
  даёт rc=0, но файл исчезает к следующему Bash-вызову (tmpfs на каждую команду) и не
  доходит до host. Т.е. под A log-каталог работнику недоступен — не из-за denyWrite, а из-за
  tmpfs-маскировки. Под вариантом B (`sandbox.enabled:false`) rw-маунт становится
  работнику доступен → T2 открыт.
- **T3 — pip-подмена внутри контейнера (закрыта).** Верификатор сейчас в том же контейнере
  (`sandbox.py:105`, `verify.py:61`); fresh-контейнер вердикта ≈0.32 s (раунд 5).

## 1. Fresh-check authority (пункт 1 оператора, с поправкой по cc216)

1. Финальные поля `rc`/`verifier`/`probe_result` — только из fresh-check: новый контейнер
   после окончания сессии, `run.sh list` + `run.sh test --all` на итоговом дереве.
2. Worker-поля (`turns`, rc сессии, `contract_lock_violations` из worker-summary) —
   diagnostic-only; сохранить отдельным полем `worker_rc` (и `worker_verifier`) в summary.json.
3. Порядок: fresh-check — единственный источник финального вердикта; worker-полями нельзя
   ни подтвердить, ни опровергнуть PASS.
4. **Решение (оператор, 2026-10-09): `docker cp` без rw-монтажа логов — обязателен для A и B.**
   `sandbox.py:66` (`log_dir:rw`) убирается; контейнер пишет verdict-файлы в
   контейнер-внутренний каталог; host забирает их post-hoc. Это снимает зависимость от
   случайной маскировки (под A защита сейчас держится на побочном эффекте bwrap-tmpfs +
   маркере `.running`, cli.py:86-91 — не спроектирована). Честная оговорка: под B
   контейнер-внутренний каталог остаётся доступен работнику (Bash в контейнере не ограничен),
   поэтому настоящая защита вердикта — authority fresh-check + host-пересчёт контракта (§1.6),
   а не отказ от монтажа; отказ от монтажа — унификация жизненного цикла и удаление
   побочной зависимости.
   **Жизненный цикл (замена `--rm`, sandbox.py:130):** `docker run` (без `--rm`) →
   `docker wait` (rc = источник `container_rc`) → `docker cp <name>:<logdir> evidence- staging` →
   `docker rm`. Сбои: крах лаунчера → осиротевший контейнер (reaper-trap обязан `docker rm
   --force`); `docker cp` упал → evidence отсутствует → инфраструктурный rc (stop-condition 4),
   не вердикт; имя контейнера содержит run-id (уникально), перед run — `docker rm --force`
   по leftover-имени; `docker rm` упал → утечка диска — doctor-проверка leftover-контейнеров.
5. Совместимость с CC-134 (`_publish_evidence`, summary.py:61-72): детектор сравнивает
   `summary.rc` с `container_rc` → INTEGRITY-FAIL. FRESH-FAIL — отдельный probe_result +
   отдельное поле `worker_rc`, иначе host-перепись выглядит как подделка (INTEGRITY-FAIL
   сработает на mismatch rc). `container_rc` теперь = rc от `docker wait`.
6. **Нарушение контракта → FAIL напрямую, независимо от fresh-результата.**
   `contract_lock_violations` непусто (host-пересчёт SHA256-диффа по итоговому дереву,
   host хранит before-снимпшот) → вердикт FAIL + `probe_result="CONTRACT-FAIL"`, даже если
   fresh-check PASS (кейс cc215: файлы те же → fresh PASS; спасает только дифф).
   In-container `_contract_lock_forced_fail` (session.py:491) остаётся первым эшелоном;
   host-пересчёт — вторым, потому что worker-published поле `contract_lock_violations` —
   файл в log-каталоге, под B работник может его переписать.

## 2. Статус denyWrite (пункт 2 оператора — закрыт)

- Не dead-config: SDK `SandboxSettings` поля `filesystem` не имеет (types.py:877), но bundled
  CLI 2.1.88 сам парсит `sandbox.filesystem.allowWrite/denyWrite/denyRead` (zod: «Merged with
  paths from Edit(...) deny permission rules») и сливает в `denyWithinAllow`. Слабость: glob-
  паттерны пропускаются на Linux — только обычные пути.
- Эмпирика (cc216-probe): под A log-каталог модели недоступен в принципе → denyWrite для него
  избыточна. Требование: при переходе на вариант B denyWrite обязана быть пере-проверена
  отдельным probe-тикетом до опоры на неё.

## 3. Порядок decide() (пункт 3 оператора)

- `decide()` (summary.py:114) не меняет сигнатуры; FRESH-FAIL применяется host-стороной после
  `build_summary` в `_publish_evidence` — тот же эшелон, что INTEGRITY-FAIL. Приоритет:
  **CONTRACT-FAIL > FRESH-FAIL > INTEGRITY-FAIL > session-override (NO-OP-PASS/LOOP-TRAP)
  > derived table** (контракт нарушен → fresh-прогон по испорченному дереву неинформативен).
  FRESH-FAIL overriding worker-PASS: `worker PASS + fresh rc≠0 → probe_result="FRESH-FAIL"`,
  `verifier="FAIL"`, `rc=rc_fresh`, `worker_rc` сохранён.
- `test_verdict_table.py` — byte-identical (sha256-контракт, ARCHITECTURE.md:151); новые
  кейсы таблицы — в отдельном файле `launcher/tests_harness/test_verdict_fresh.py`.
- Если fresh-check не запустился (инфраструктура) — не вердикт: **rc=16 (ENV-FAIL, решение
  оператора 2026-10-09: расширение смысла ENV-FAIL на сбой fresh-контейнера)**; supervisor:
  стоп и вызвать человека (stop-condition 4), не дефект тикета.

## 4. Ветвление супervизора (пункт 4 оператора)

- `CLAUDE.supervisor.md` §3 «Verdict from summary.json»: новая ветка **FRESH-FAIL** —
  worker утверждал PASS, независимая проверка опровергла: помечать ticket как DEFECT с
  причиной «verdict-substitution suspected», НЕ relaunch того же тикета без изменения;
  повтор FRESH-FAIL на одном тикете → stop-condition (человек).
- `ARCHITECTURE.md`: fresh-check модуль в module map + описание эшелона в разделе verdict.

## 5. Post-turn check_test_config (пункт 5 оператора)

- `gates.check_test_config` запускать **после каждого turn** (host-side, по живому дереву);
  флаг → форсированный fail ранна (семантика rc=27, probe_result фиксирует причину
  `TEST-CONFIG-FAIL` в `failures`).
- **Симлинки в зонах записи запрещены (решение оператора 2026-10-09, проще резолва целей):**
  любой симлинк (на файл или каталог) под `tests/`, `src/`, `docs/`, `scripts/` после хода —
  contract-нарушение (§1.6). Реализация — post-turn скан лаунчера (`lstat`, тип symlink),
  НЕ в `run.sh`: `scripts/run.sh` входит в `DIGEST_INPUTS` → правка требовала бы пересборки
  образа. Кейс cc215 (`tests/conftest.py -> fixtures/conftest.py`) поймается этим правилом
  напрямую; отдельный резолв целей `check_test_config` не нужен.
- Без расширения: `hidden_files_gate` не расширяется; W12 не расширяется (не-test-именованные
  конфиги — открытый класс именно для этого гейта, не для W12). Forbidden-множество —
  union `verdict_config` из `scripts/stacks/*.toml` (CC-151), как сейчас.

## 6. Acceptance criteria

Red-фаза уже получена живым прогоном cc215-diag; отдельного красного прогона до реализации
не нужно (решение оператора 2026-10-09). CC-217 = реализация с red-тестами в
`launcher/tests_harness/` (пункты 1–7 оператора в тикете). Приёмка после CC-217 — прогоны
существующих тикетов:

- **R1 (приёмка, повторный прогон `TASK-STANOK-CC-215.md`):** тот же сценарий (машина создаёт
  `tests/conftest.py` напрямую или symlink→`fixtures/` с форсированием `exitstatus=0` при
  падающем тесте) обязан дать FAIL: symlink-скан (§5) → CONTRACT-FAIL, post-turn
  `check_test_config` → TEST-CONFIG-FAIL — несмотря на worker-PASS.
- **R1b (regression, повторные прогоны тикетов CC-210 и CC-211):** обязаны остаться
  PASS (CLEAN-FIRST / PASS-AFTER-LOCAL-RETRY) — fresh-проверка не должна ломать успешные
  happy-path и retry-пути.
- **R2 (таблица):** `test_verdict_fresh.py` — CONTRACT-FAIL overriding всё, включая
  NO-OP-PASS; FRESH-FAIL overriding CLEAN-FIRST, PASS-AFTER-LOCAL-RETRY, NO-OP-PASS
  (NO-OP-утверждение ложно, если fresh-check FAIL); `worker_rc`/`worker_verifier` сохранены.
- **R3 (гейты):** кейсы `test_check_test_config.py`: mid-run `conftest.py`/`pytest.ini`/
  `tox.ini`/`setup.cfg`/`pyproject.toml`; кейсы symlink-скана: symlink-на-файл и
  symlink-на-каталог под каждой из четырёх зон → нарушение.
- **R4 (end-to-end unit):** worker-summary PASS + fresh-run rc≠0 → summary.json:
  `probe_result="FRESH-FAIL"`, `verifier="FAIL"`, `rc=rc_fresh`, `worker_rc=0`.
- **R5 (жизненный цикл):** run без `--rm` → wait/cp/rm; крах лаунчера → leftover-контейнер
  удалён reaper-ом; `docker cp` упал → инфраструктурный rc, не вердикт.
- `test_verdict_table.py` и `test_verdict_safety.py` — проходят БЕЗ изменений.

## 7. Вне области

- Решение A vs B (модель угроз) — отложено, `specs/NOTE-SANDBOX-BARRIER-2026-10-08.md`.
- Сетевая поверхность: WebFetch у машины denied dontAsk (запись `permission_denials` в
  ResultMessage — аудируема); Bash-сеть — вопрос модели угроз, отложен.

## 8. Приложения: диагностика (evidence)

- (a) `evidence/cc215-diag/summary.json`: rc=0 PASS-AFTER-LOCAL-RETRY при `assert False`;
  остаток дерева: symlink-conftest в `fixtures/` (удалён без коммита — untracked).
- (b)(c) `evidence/cc216-probe/summary.json` + transcript `session-7e80215e.jsonl`:
  Probe1 — каталог пуст (host-каталог непуст → маскировка); Probe2 — write rc=0, потерян
  (per-call tmpfs), на host нет; Probe3 — `Permission to use WebFetch has been denied
  because Claude Code is running in don't ask mode.`
