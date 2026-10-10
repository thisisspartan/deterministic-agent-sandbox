# SPEC-NETWORK-PROD — production-ready сетевая изоляция (Compose + Envoy)

> Источник: задание оператора 2026-10-09 (ревью Compose+Envoy-плана с четырьмя поправками).
> Статус (решение оператора 2026-10-09): **согласовано только X1** — выполняется первым
> в изолированном worktree. Реализацию Compose + Envoy (R3–R6) НЕ начинать. После X1 —
> реальные результаты и обновлённый SPEC. X4 и X5 — обязательные условия production-приёмки.
> Линия E1–E4/S5 (PLAN-SIMPLIFY §3) отложена оператором; S4 (`1f394bc`, SPEC-NETWORK-2026-10-09)
> реализована и остаётся действующей сетью до миграции; её systemd-юнит НЕ установлен.
> Движок: Docker Engine 29.1.3 (хост). Kubernetes — только интерфейс backend'а, не реализация.

## 1. Живые факты (проверено командами, 2026-10-09)

- Docker Engine/CLI хоста: **29.1.3** (`docker version`) — ≥ 28.0.0, т.е. режим
  `gateway_mode_ipv4: isolated` по версии доступен.
- **isolated проверен живьём**: `docker network create --internal -o
  com.docker.network.bridge.gateway_mode_ipv4=isolated zz-isolated-test` — сеть создана,
  у host-side bridge-интерфейса `br-…` **нет IPv4-адреса** (`ip -o addr`); контрольный
  обычный мост br-fe9cd151effb (stanok-net) имеет 172.28.0.1. Тестовая сеть удалена.
- Модель: llama-server **192.168.8.131:8080** (REMOTE LAN; `/props` отвечает). На хосте
  llama-server нет. Хост: 192.168.122.156/24, шлюз 192.168.122.1.
- Opik: слушает **0.0.0.0:8080** и **0.0.0.0:5173** (`ss -tlnp`).
- Worker-контейнер СЕЙЧАС: `--network=stanok-net` (S4) + `--security-opt seccomp=unconfined`
  + `--security-opt apparmor=unconfined` (`launcher/sandbox.py:188-190`) +
  `enableWeakerNestedSandbox: true` (`.claude/settings.stanok.json:55`).
  **Прямое противоречие требованию 1** → снимается только экспериментом X1 (§5), не молча.
- `sandbox.network.allowedDomains` сейчас: `192.168.8.131, localhost, 127.0.0.1, pypi.org,
  files.pythonhosted.org, registry.npmjs.org, deb.debian.org, security.debian.org`.
  Реестры — мёртвый вес: STANOK-NET их DROP'ит, CLAUDE.md запрещает пакеты из сети.
- Пути сетевого трафика разделены по конструкции: CLI-процесс (запросы модели) использует
  `ANTHROPIC_BASE_URL` (`session.py:112`) вне песочницы; Bash внутри нативного sandbox
  выходит только через прокси `allowedDomains` (socat-мост). Поэтому «Bash к listener
  не достанет, CLI достанет» — проверяемое свойство, а не предположение.
- Использования `cfg.server_url` (полный список, все подлежат исправлению по R2):
  `config.py:37` (поле), `config.py:68` (env STANOK_SERVER_URL), `session.py:112`
  (ANTHROPIC_BASE_URL работника), `gates.py:350-356` (`_fetch_server_props`),
  `gates.py:461` (сетевой зонд), `sandbox.py:253-266` (`probe_argv`), `cli.py:214`
  (CLI-сообщение), тесты `test_server_preflight_import.py`, `test_network_preflight.py`.
- Opik-эндпоинты сейчас: host-side `STANOK_OPIK_URL` (default `http://localhost:8080`,
  `opik.py:29`); worker-side `BETA_TRACING_ENDPOINT=http://localhost:8080/v1/private/otel`
  (settings.stanok.json env) — с моста S4 недоступен (поле `opik_traces="disabled"`).
- Отказ bwrap на отдельной Bash-команде НЕ фиксируется: `failIfUnavailable=true` ловит
  только отсутствие bwrap при старте CLI; внешний verifier гоняет сюиту вне bwrap →
  вердикт PASS возможен при неработающем Bash модели. Gap подтверждён кодом.
- Firewall-backend Docker (iptables+DOCKER-USER vs nftables) на хосте НЕ проверен:
  нет passwordless sudo → требует подтверждения оператором (X5).
- Подсети: docker0 172.17.0.0/16, opik_default 172.25.0.0/16, stanok-net 172.28.0.0/16.
  172.29.0.0/16 и 172.30.0.0/16 на хосте не заняты (проверка `ip -o addr`/docker network ls).

## 2. Инварианты (неизменяемые)

- **I1.** Claude Code 2.1.88, встроенный Bash, bwrap, работа с worktree, существующий
  launcher — сохраняются.
- **I2.** Запрещены: `network_mode: host`, `privileged`, `seccomp=unconfined`,
  `apparmor=unconfined`, Docker socket внутри worker, ручные действия оператора после
  установки.
- **I3.** `enableWeakerNestedSandbox` не включается автоматически: сначала bwrap с обычными
  профилями защиты (X1). При неудаче — останов, точная диагностика, минимально необходимое
  изменение (решение оператора).
- **I4.** Нет скрытого fallback между upstream модели и gateway: каждый адрес явный,
  отсутствие обязательного адреса = ошибка запуска.
- **I5.** Семантика вердикта не меняется: вердикт = утверждение о дереве (S2/S3);
  отказ песочницы не может дать PASS.

## 3. Требования

### R1. Воспроизводимость worktree + обработка отказов bwrap
- Детерминированная подготовка ДО запуска песочницы (host-side, в `_host_launch`):
  обязательные каталоги/файлы (`evidence/<label>/`, настройки) создаются launcher'ом;
  независимость от содержимого основного checkout (основание — инцидент rc=28: отсутствующий
  `evidence/` в worktree). Ошибка «путь отсутствует/недоступен для записи» не может быть
  принята за несовместимость bwrap.
- Обработка отказа bwrap на уровне отдельного вызова Bash: launcher фиксирует сбой песочницы
  (сигнатура ошибки bwrap в tool-потоке CLI) → итоговый статус прогона **ENV-FAIL (rc=16)**;
  внешний verifier продолжает гонять сюиту вне песочницы, но зафиксированный bwrap-отказ
  понижает вердикт до ENV-FAIL. Текстовое утверждение модели «Tests: PASS» не участвует
  в вердикте (уже так: вердикт выдаёт verifier).
- Механизм фиксации — по правилу KISS (§7 CLAUDE.supervisor.md): цитировать инцидент
  (rc=28, gap из §1) или нативную примитиву cli.js; конкретный механизм выбирается на
  этапе реализации, SPEC фиксирует только семантику (bwrap-отказ → ENV-FAIL).

### R2. Разделение адресов (четыре адреса, явных)
- `model_upstream` — реальный upstream модели (`http://192.168.8.131:8080`): host-side
  preflight (`_fetch_server_props`), host-кросс-проверка сетевого зонда, CLI-сообщения.
- `gateway_model_url` — listener Envoy для Claude Code внутри worker: `ANTHROPIC_BASE_URL`.
- `opik_host_url` — хостовый адрес Opik для host-side проверок (`opik_traces`).
- `gateway_tracing_url` — listener Envoy для отправки трейсинга из worker
  (`BETA_TRACING_ENDPOINT`).
- Исправляются ВСЕ использования `cfg.server_url` из §1. Каждый адрес — отдельный
  конфигурационный вход (env-имена фиксируются при реализации). Fallback запрещён (I4):
  при запуске в Compose-режиме отсутствие `gateway_model_url` → ошибка запуска.

### R3. Docker Compose + Envoy TCP gateway
- Две сети:
  - `worker-net`: `internal: true` + `driver_opts: com.docker.network.bridge.gateway_mode_ipv4: isolated`
    (подсеть фиксированная, не пересекается с §1-перечисленными);
  - `egress-net`: сеть исходящего подключения Envoy (отдельная подсеть).
- Подсети НЕ являются константами (поправка оператора 2026-10-09): 172.29/172.30 — лишь
  свободные на ЭТОМ хосте значения. Развёртывание обязано проверить конфликт с LAN/VPN/
  существующими docker-сетями и завершиться ошибкой при конфликте (без тихого выбора).
- `claude-worker` подключён только к `worker-net`. Envoy подключён к обеим сетям и имеет
  ровно два статических TCP-upstream: модель `192.168.8.131:8080` и фактический endpoint
  Opik (адрес из R5).
- Envoy не публикует listener-порты (`ports:` отсутствуют); административный интерфейс
  отключён либо ограничен loopback.
- Worker ↔ Envoy: единственный сетевой путь работника — listener Envoy внутри worker-net
  (internal-сеть разрешает трафик внутри своей сети; isolated убирает только host-side IP).
- Проверка совместимости при установке и при запуске: engine ≥ 28.0.0 и создание
  internal+isolated сети (живой probe) — при недоступности обязательного режима запуск
  завершается **ошибкой**, без тихого fallback (I4).
- Единственный источник истины запуска worker (compose.yaml или docker-run argv в sandbox.py)
  — выбирается при реализации; SPEC фиксирует сетевой контракт, дрейф двух источников —
  угроза T6 (§6).

### R4. Egress-политика Envoy — часть установки
- Конфигурация Envoy НЕ является доказательством изоляции: сам контейнер Envoy на обычной
  сети имеет полный egress. Требуется политика: ровно два разрешённых назначения
  (модель, Opik), всё остальное — DROP.
- Предпочтительный механизм: расширение существующего STANOK-NET-паттерна (цепь + прыжок
  по `-s <подсеть egress-net>`; ACCEPT только двух назначений + RELATED,ESTABLISHED).
  Если текущий механизм недостаточен — отдельный автоматически управляемый backend.
  Ручные iptables/nftables-команды оператора запрещены (I2).
- **X5 — обязательное условие production-приёмки (поправка оператора 2026-10-09):**
  установка сетевой политики — повторяемый компонент развёртывания: идемпотентная
  установка, проверка состояния, обновление, удаление. Если подходящий backend нельзя
  установить и проверить — защищённый режим отказывается запускаться (rc=16).
- Учитывается реальный firewall-backend Docker (DOCKER-USER может отсутствовать при
  nftables): backend определяется, а не предполагается (X5).
- Если политика не может быть установлена И проверана — защищённый запуск завершается
  отказом (семантика rc=16).
- Kubernetes: отдельная реализация через NetworkPolicy кластера; интерфейс общий —
  «сетевой policy-backend» (установить + проверить). Один Compose-файл не универсален.

### R5. Opik
- Opik остаётся включённым только если привязан к адресу интерфейса `egress-net` и закрыт
  от других интерфейсов. `0.0.0.0:8080` не оставляем; `5173` не открывается в LAN ради
  трейсинга. Привязка — настройка host-side (оператор), проверяется preflight'ом.
- Если привязка на текущем хосте недостижима — отправка трейсинга временно отключается
  ЯВНО (поле `opik_traces="disabled"`, уже существует), а не через `0.0.0.0`.
- Трейсинг из worker идёт через Envoy (`gateway_tracing_url`); host-side проверка —
  `opik_host_url`.

### R6. Runtime allowlist
- Удалить из `sandbox.network.allowedDomains`: `pypi.org`, `files.pythonhosted.org`,
  `registry.npmjs.org`, `deb.debian.org`, `security.debian.org` (мёртвый вес, §1).
- Listener Envoy НЕ добавляется в allowlist Bash (иначе Bash обходит политику).
- Итоговый allowlist: пустой либо `localhost`-минимум — зависит от X3 (поведение CLI при
  пустом allowlist с `sandbox.enabled=true` не проверено).
- CLAUDE.md скорректирован (S4 уже запрещает пакеты из интернета — проверить формулировку
  после смены сети).

## 4. Матрица приёмочных тестов

Все отрицательные проверки выполняются **настоящим встроенным Bash через Claude Code**
(не `docker exec`).

Отрицательные (из Bash работника — отказ обязателен):
- N1 прямой доступ к `192.168.8.131:8080`;
- N2 прямой доступ к обоим listener Envoy (каждому отдельно);
- N3 прямой доступ к Opik (host-адрес и egress-net-адрес);
- N4 SSH хоста, порт 22;
- N5 произвольный внешний адрес (1.1.1.1:80);
- N6 обходные маршруты: IPv4 (другие подсети/шлюз) и, если IPv6 включён, IPv6.

Положительные:
- P1 Claude Code получает ответ модели через Envoy (сессия проходит);
- P2 Opik принимает трейсы через Envoy (счётчик трейсов растёт);
- P3 Bash работает и выполняет тесты в bwrap (красная/зелёная фазы TDD состоялись);
- P4 искусственный отказ bwrap → прогон классифицирован ENV-FAIL, вердикт не PASS.

Инфраструктурные:
- I1 исходящий трафик Envoy ограничен двумя назначениями (зонд из контейнера Envoy:
  модель OK, Opik OK, всё остальное refused);
- I2 ошибка конфигурации или отсутствие сетевой политики обнаруживаются ДО запуска worker
  (preflight, rc=16);
- I3 engine < 28.0.0 / isolated недоступен → ошибка запуска, без fallback.

## 5. Эксперименты (до реализации; часть согласования)

- **X1 (гейт) — СОГЛАСОВАН оператором 2026-10-09: выполняется первым, в изолированном
  worktree** (реальные Claude Code 2.1.88 + bwrap, обычные профили Docker seccomp/AppArmor,
  `enableWeakerNestedSandbox=false`; логи запуска/Bash сохраняются). bwrap с обычными профилями: убрать `seccomp=unconfined`,
  `apparmor=unconfined`, `enableWeakerNestedSandbox` → живой прогон машины. Успех =
  базовая конфигурация для всех дальнейших шагов. Неудача = останов + точная диагностика
  (какой профиль/syscall блокирует) + минимально необходимое изменение (решение оператора).
  - **РЕЗУЛЬТАТ X1 (выполнен 2026-10-09, worktree stanok-x1@`758383d`, тикет CC-210, label `x1`): НЕУДАЧА — bwrap
    невозможен с обычными профилями на этом хосте/образе.** Прогон: rc=0, verifier PASS, CLEAN-FIRST — но Bash
    модели падал 12×: `bwrap: No permissions to create new namespace` (12 идентичных отказов). Точная диагностика
    (docker-probe матрица security-opt × `unshare`/`bwrap` в образе):
    * default seccomp блокирует `unshare` (unprivileged userns) → `Operation not permitted`;
    * `seccomp=unconfined` + default AppArmor: `unshare` OK, но bwrap падает на `Failed to make / slave:
      Permission denied` (AppArmor docker-default блокирует mount/propagation);
    * BWRAP-OK только при обоих unconfined = текущая prod-конфигурация.
    Хост: kernel.unprivileged_userns_clone=1, AppArmor включён → блокировка не sysctl, а профили Docker.
    **Побочный живой факт (подтверждение X4):** вердикт PASS при НУЛЕ успешных песочничных Bash-команд —
    модель завершила TDD через Write + харнесс-хуки (red подтверждён хуком вне песочницы) + внешний verifier.
    Логи: /tmp/stanok-logs/x1/ (session-4aabf9e7.jsonl, summary.json). Решение о минимально необходимом
    изменении (custom seccomp-профиль + custom AppArmor-профиль vs сохранение unconfined + X4) — за оператором.
- **X2.** Worker на internal+isolated worker-net достигает только listener Envoy
  (intra-network OK, host-side IP нет) — живая проверка структуры (isolated уже
  подтверждён на тестовой сети, но не с работником).
- **X3.** Поведение CLI/Bash при пустом `allowedDomains` и `sandbox.enabled=true`.
- **X4 — обязательное условие production-приёмки (поправка оператора 2026-10-09).**
  Механизм фиксации per-call bwrap-отказа (R1): candidate — разбор tool-потока
  CLI на сигнатуры песочницы; проверить нативные примитивы cli.js/SDK до изобретения.
  Требование приёмки: если агент не смог выполнить песочничные команды, внешний verifier
  НЕ выдаёт PASS — прогон классифицируется ENV-FAIL (P4).
- **X5 — обязательное условие production-приёмки (поправка оператора 2026-10-09).**
  Firewall-backend хоста (iptables+DOCKER-USER vs nftables) — требует root;
  подтверждает оператор. Установка политики как повторяемого компонента развёртывания —
  см. R4 (идемпотентная установка / проверка состояния / обновление / удаление).

## 6. Угрозы

- **T1.** Компрометация Envoy = дыра, если его egress не ограничен (закрывается R4).
- **T2.** Vacuous-pass зондов на хостах без интернета/sshd (известная оговорка
  SPEC-NETWORK) — приёмка на ЭТОМ хосте, где оба условия реальны.
- **T3.** Mid-run изменение политики хостом после preflight не перепроверяется (snapshot).
- **T4.** bwrap в контейнере с обычными профилями может оказаться невозможен (kernel
  seccomp/apparmor) — решает X1; молчаливое ослабление запрещено (I3). **ПОДТВЕРЖДЕНО X1 (2026-10-09):
  невозможен** (см. РЕЗУЛЬТАТ X1 в §5) — stop-условие §8 сработало, решение за оператором.
- **T5.** Opik 0.0.0.0:8080 открыт в LAN — закрывается R5 или явным отключением трейсинга.
- **T6.** Дрейф двух источников запуска worker (compose.yaml vs sandbox.py argv) —
  один источник истины, второй запрещён.

## 7. Порядок миграции

1. X1 — гейт (без него I2/I3 недостижимы).
2. R2 (разделение адресов) — host-side, red-first, харнесс-регрессия (Docker/no-Docker).
3. R3 + R4 + R5 + R6 — Compose, Envoy, сети, egress-backend, Opik-привязка, allowlist.
4. Матрица §4 живыми прогонами.
5. Решение о судьбе S4-механизма (stanok-net/STANOK-NET): переиспользовать как backend R4
   или заменить worker-net/egress-net — на этапе реализации, после X5.

## 8. Условия отказа (stop-условия)

- X1 показал невозможность bwrap без unconfined → останов, диагностика + минимальное
  изменение на решение оператора.
- Engine не поддерживает isolated → запуск завершается ошибкой (не fallback).
- Egress-политика не устанавливается/не проверяется → защищённый запуск отказывает (rc=16).
- Opik нельзя привязать к egress-net → трейсинг явно отключён (не 0.0.0.0).

## 9. Статус утверждений (честная разметка)

- **Проверено на хосте:** Engine 29.1.3; isolated работает (live-тест §1); факты текущей
  конфигурации (allowedDomains, enableWeakerNestedSandbox, security-opt флаги, Opik
  0.0.0.0, список server_url, gap bwrap→PASS, занятые подсети).
- **Следует из документации Docker:** isolated требует internal; параметры bridge-драйвера
  через driver_opts; поведение Engine 28+.
- **Подтверждено экспериментом (выполнено 2026-10-09):** X1 — bwrap с обычными профилями НЕвозможен
  (default seccomp: unshare; default AppArmor: mount); PASS при нуле песочничных Bash (живой X4-gap).
- **Требует эксперимента (не выполнено):** X2, X3, X4 (механизм), X5; вся матрица §4; поведение worker в
  isolated-сети; итоговый allowlist.

Ни один пункт из третьей колонки не отмечается как выполненный.
