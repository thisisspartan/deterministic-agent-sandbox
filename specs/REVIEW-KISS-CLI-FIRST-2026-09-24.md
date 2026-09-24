# REVIEW — KISS / over-engineering: «cli.js first» (2026-09-24)

Вход: `PLAN-T2-PREFLIGHT-2026-09-24.md` §6 (BLOCKED on this review), `SPEC-STANOK-HARNESS-REVIEW.md`,
`HANDOFF-ARCH-REVIEW.md`, `stanok/launcher/stanok.py` (1864 стр.), `sandbox.py`, `README.md` §139-393.
Все native-факты сверены с pinned `~/git/claude-code-2.1.88/cli.js` и SDK `0.2.139` (`types.py`).

## 0. Вердикт (TL;DR)

1. **Корень «колхоза» не в архитектуре, а в процессе:** механизм добавляется под каждый инцидент
   и **никогда не снимается**. Отсюда 1864 строки, ~8 гейтов, 2 манифеста, свой retry-loop,
   свой резолвер путей cli.js и словарь «v4.2» (Control Plane / Data Plane / POSIX ABI / FSM).
2. **Направление = «cli.js first»**, формализовать как инвариант: *прежде чем писать логику в
   харнессе — grep pinned cli.js/SDK; если примитив есть — конфигурировать его, а не повторять.*
3. **T2 = Option B** (quarantine retirement + W2.4 backstop + честный NO-OP). Направление A
   (probes/oracle/rc=29/30) — отклонить: это +3 механизма и +2 rc-кода против **уже существующего
   грила** и **уже существующего W2.4**.
4. Есть **4 конкретных механизма-дублёра**, которые надо удалить/сжать механически (Kill-list, §3).
   Всё остальное — неснижаемый транспорт и настоящие инварианты (Keep-list, §4).

## 1. Принцип «cli.js first» (чем заменять)

Нативные примитивы, релевантные харнессу (проверено):

| Native (cli.js / SDK 0.2.139) | Факт |
|---|---|
| Hook-события | `PreToolUse, PostToolUse, Stop, SubagentStop, PreCompact, SessionStart, SessionEnd, UserPromptSubmit, Notification` — все есть (`cli.js`); in-process колбэки — `ClaudeAgentOptions.hooks` (`types.py:2064`) |
| Блокирующий `Stop` hook | `decision`/`stopReason` в `cli.js` (48/14 вхождений) — CLI сам может пере-пригласить модель; семантику проверить перед adopt |
| Permission-режимы и правила | `permission_mode` (`dontAsk`/`acceptEdits`/…), `deny`-правила `Read(...)`/`Edit(...)` — уже используются |
| Native sandbox | `sandbox.filesystem.allowWrite/denyWrite`, `sandbox.failIfUnavailable` — уже используется |
| Worktree | `--worktree` (`cli.js`, 15 вхождений) + инструмент `EnterWorktree` |
| Resume/fork, лимиты | `resume`, `fork_session`, `max_turns`, `setting_sources` (`types.py:1941/1939/1951/2046`) |
| Стриминг/схема | `--output-format stream-json`, `--include-partial-messages`, `--json-schema` |
| Compaction | `CLAUDE_CODE_AUTO_COMPACT_WINDOW` / `CLAUDE_AUTOCOMPACT_PCT_OVERRIDE` — уже стоят в settings |
| Фоновый агент | **нет** `--bg` в 2.1.88 (ADR-agent-view §Q2/§V) → процесс-супервизия остаётся своей |

## 2. Инвентарь: механизм станка ↔ native ↔ вердикт

| Механизм (`stanok.py`/`sandbox.py`) | Инцидент, который закрывает | Native-аналог | Вердикт |
|---|---|---|---|
| `run_continuous_session` + `<verification_result>` retry-loop | ретраи внутри одной сессии (KV-кэш) | `Stop` hook (block) / `resume` | **KEEP** — вердикт внешний (host), in-container hook его не даст |
| `_pretooluse_lock_hook` + `_tests_manifest` (contract_lock) | ослабление pre-existing тестов/`run.sh` | нет прямого (deny-правило не различает новый TDD-файл) | **KEEP** (это настоящий инвариант) |
| `_verifier_hook` (RED-CONFIRMED) | TDD-дисциплина | PostToolUse hook — уже native-механизм | **KEEP** |
| `_resolve_sandbox_path` + `sandbox_config_gate` | CC-075/CC-107 (EROFS на первом Bash) | cli.js сам резолвит пути | **DELETE** (§3.1) |
| `prepare_workspace` (quarantine→pre-existing) | stale-артефакт маскирует NO-OP | worktree не годится (HEAD уже содержит артефакты, отказ зафиксирован) | **KEEP** |
| W2.4 zero-writes backstop (~5 стр.) | NO-OP без probes | — | **KEEP** |
| `preflight_server` (n_ctx) | локальный llama-server: маленькое окно | у CLI нет мнения о `/props` | **KEEP** |
| `_stack_preflights` / `_image_digest` / `preflight_image` | готовность раннера/образа | — | **SIMPLIFY** → один doctor-чек (§3.2) |
| `_extract_smart_diff` + `NOISE_LINE_PATTERNS` | сжатие ошибок для fix-prompt | нет; и сам HANDOFF §5.3 его помечает JS/TAP-перекосом | **SIMPLIFY** → сырой хвост (§3.3) |
| `hidden_files_gate` / `test_config_gate` | утечка dotfile/TEMP; `conftest.py` подменяет вердикт | CLI не знает чужой тест-раннер | **KEEP** (узкие, реальные) |
| marker `.running`, flock rc=21, `status`/`stop`, `docker_stop`, turn-watchdog | единственный слот сервера; нет `--bg` в 2.1.88 | — | **KEEP** (неснижаемый транспорт) |
| Probes / `oracle:` / rc=29/30 (план T2-A) | невыполнимый тикет; SATISFIED-гейт | grill (supervisor) + W2.4 уже это делают | **DELETE** (§2.1) |
| Словарь README «v4.2»: Control/Data Plane, POSIX ABI, Namespace Separation, FSM | — | — | **DELETE** (нарратив, §3.4) |

### 2.1 T2: почему Option B, а не A

- **Infeasible-тикет** (числовой контракт 0.6938 < 0.75) — это провал **грила**, а не рантайма:
  супервизор обязан поймать его до запуска (`CLAUDE.supervisor.md` §1). Probe дублирует грил,
  но пишется в спешке (ad-hoc скрипт под тикет) и потому менее надёжен, чем человек.
- **Already-satisfied** уже ловит W2.4 (turn1 + 0 Write/Edit), бесплатно.
- Цена A: `probe:`-метастрока в парсере, `_run_probe_safely` (killpg/таймаут), **два новых rc**,
  перенос записи `.running` (R8), правки settings (R9), новая supervisor-зона `probes/`,
  двойной парсинг тикета (R10) — ровно тот класс механики, из которого выросли текущие 1864 строки.
- Единственное, что A даёт сверх B: **экономия времени** на заведомо мёртвом тикете. Это не
  инвариант корректности, а оптимизация — вводить её без инцидента нельзя (принцип §0.1).

## 3. Kill-list (механические удаления/сжатия)

**3.1 `_resolve_sandbox_path` + `sandbox_config_gate` (stanok.py:255-298) — DELETE.**
Функция явно «Mirror cli.js Rn6/lq» и моделирует `V_6` (базу `flagSettings`) — это повторная
реализация нативного резолвера, из-за которой и случился CC-075. Замена: (а) в settings писать
пути, которые **существуют** (`../.git`, `../hooks`); (б) вместо модели cli.js — один literal
existence-check без претензии на семантику. Крайний случай (EROFS) ловится native
`failIfUnavailable` + первым Bash-вызовом, а не питоновским предсказанием.

**3.2 `_stack_preflights` + `_image_digest`/`preflight_image` — УЖЕ СДЕЛАНО (CC-106).**
`preflight_image` больше не на launch-path (нет `early_abort(25)`); его вызывает только
doctor (`test_doctor.py::test_docker_image_digest_matches`). Резидуал закрыт в CC-123:
устаревшие «rc=25» в логах и в stop-conditions `CLAUDE.supervisor.md` убраны (rc=25
недостижим; provenance образа — doctor-чек). Отдельный модуль для этих функций не
выделялся — перенос без инцидента был бы рефакторингом ради рефакторинга.

**3.3 `_extract_smart_diff` + `NOISE_LINE_PATTERNS` — SIMPLIFY до сырого хвоста.**
Приоритетный regex — JS/TAP (`strictequal`, `not ok N`), для Python только низший тир
(HANDOFF §3 #9). Эвристика, которая может исказить сигнал, хуже, чем «последние N строк вывода».
Фикс-промпт и так adaptive.

**3.4 README §139-393 «Архитектура v4.2» — DELETE (словарь, не код).**
Control Plane / Data Plane / Inference Gateway / POSIX ABI / Namespace Separation / FSM описывают
обычные компоненты (python-супервизор, docker, run.sh, rc-коды). Этот слой языка и создаёт
ощущение «запутались»: он заставляет искать архитектуру там, где её нет. Оставить фактическое
описание (§49-138) и таблицу rc.

## 4. Keep-list (неснижаемое — не трогать)

Процесс-супервизия (marker/flock/status/stop/watchdog) как транспорт (в 2.1.88 нет `--bg` —
ADR); **внешний** `verify_gate` (out-of-band арбитраж — это продукт, а не костыль);
contract_lock (эшелон 1 hook + эшелон 2 SHA-diff); `_verifier_hook`; `preflight_server`;
`test_config_gate`/`hidden_files_gate` (эксплуатационные эксплойты, native о них не знает);
`summary.json` + rc-таблица (контракт L1).

## 5. Defer (убрать с критического пути)

T3/T4 (динамические RW-mounts от `mutable_paths`) и T5 (снятие PreToolUse-хука) существуют,
чтобы mount-политика следовала за тикетом. В Option B это **уточнение**, а не потребность:
нет инцидента «агент пишет в зону, которую тикет не объявлял» (CC-119 лечится quarantine).
Вернуть T3-T5 только под конкретный инцидент.

## 6. Инвариант против повторения

> **Правило cli.js-first.** Любой новый механизм харнесса обязан указать либо (а) инцидент с
> эвиденсом из `evidence/`, который он закрывает, либо (б) native cli.js/SDK-примитив, который он
> заменяет. Нет ни того, ни другого — предложение отклоняется. Механизм удаляется, как только его
> класс инцидентов закрыт нативным примитивом.

Подкрепление: держать наблюдаемый budget в `doctor.sh` (число гейтов и строк `stanok.py` — печатать,
следить за ростом). Рост без строки в Kill-list = сигнал.

## 7. Что делать дальше (по порядку)

1. Принять **T2 Option B** в `PLAN-T2-PREFLIGHT` (план уже рекомендует; §2.1 выше).
2. Выполнить Kill-list 3.1-3.4 отдельными коммитами, каждый — с прогоном doctor.
3. Зафиксировать правило §6 в `CLAUDE.supervisor.md` + `CONTEXT.md`.
4. T3-T5 — в бэклог «по инциденту», не в текущий план.
