# SPEC-NETWORK — S4: мост stanok-net + сетевой preflight

> Источник: specs/PLAN-SIMPLIFY-2026-10-09.md §3 (S4), §2.7 (Opik), §2.8 (пакеты).
> Эксперимент E2 (тот же план) определяет политику: **модель доступна, внешний адрес нет,
> сервисы хоста закрыты.**

## 1. Живые факты (проверено командами, 2026-10-09)

- Модель: llama-server на **192.168.8.131:8080** (REMOTE LAN-машина; `/props` отвечает).
  На этом хосте llama-server НЕТ. `STANOK_SERVER_URL=http://192.168.8.131:8080`.
- Этот хост: 192.168.122.156/24, шлюз 192.168.122.1. Порты хоста: 8080 = opik-backend
  (0.0.0.0:8080->8080), 5173 = Opik frontend, 22 = sshd (0.0.0.0).
- Docker-сети хоста: bridge (172.17.0.0/16), host, none, opik_default (172.25.0.0/16).
  Подсеть **172.28.0.0/16 свободна** → выделяется под stanok-net.
- Worker-контейнер сейчас `--network=host` (sandbox.py) — политика E2 на нём невыполнима
  (per-container фильтрация невозможна на host-сети). Fresh-контейнер `--network=none` — не меняется.

## 2. Требования

### R1. Мост stanok-net
- Docker bridge-сеть `stanok-net`, подсеть 172.28.0.0/16 (имя/подсеть — константы,
  override через env `STANOK_DOCKER_NETWORK`).
- Worker-контейнер запускается в `--network=stanok-net` вместо `--network=host`.
- Fresh-контейнер остаётся `--network=none`.

### R2. iptables-политика (скрипт infra/stanok-net.sh)
- Цепочка `STANOK-NET` (filter, таблица filter):
  - ACCEPT `-m conntrack --ctstate RELATED,ESTABLISHED`
  - ACCEPT `-d $MODEL_HOST -p tcp --dport $MODEL_PORT`
  - DROP (всё остальное)
- Переходы (idempotent: перед вставкой удаляются существующие):
  - `DOCKER-USER` позиция 1: `-s 172.28.0.0/16 -j STANOK-NET` (FORWARD: контейнер → вовне)
  - `INPUT` позиция 1: `-s 172.28.0.0/16 -j STANOK-NET` (контейнер → сервисы хоста)
- Переменные в шапке скрипта: `NET=stanok-net`, `SUBNET=172.28.0.0/16`,
  `MODEL_HOST=192.168.8.131`, `MODEL_PORT=8080`.
- Скрипт создаёт сеть, если её нет; идемпотентен (повторный запуск безопасен).

### R3. systemd-юнит (infra/stanok-net.service)
- Type=oneshot, RemainAfterExit=yes, After=docker.service, WantedBy=multi-user.target.
- ExecStart — абсолютный путь к скрипту (путь репозитория зафиксирован в комментарии:
  ставит оператор, путь может отличаться).
- Готовит супervisor, ставит оператор (S4 handoff).

### R4. Сетевой preflight (host-only, до старта работника)
- Расположение: `cli._host_launch` после разбора тикета, до `run_sandboxed`
  (покрывает и sync, и `--follow`-ребёнка: ребёнок заново проходит main→_host_launch;
  no-sandbox путь в _host_launch не попадает). НЕ в `_launch_gates` (те执行ются в контейнере).
- Зонд: `docker run --rm --init --network=stanok-net --name stanok-stanok-netprobe-<pid> <image> /usr/bin/python3 -`
  (имя совпадает с префиксом reap_stopped `stanok-{basename(repo_root)}-`), скрипт зонда через stdin,
  `cfg.server_url` как argv[1]. Зонд печатает JSON `{model, external, host}`:
  - model: GET `{server_url}/props` (таймаут 5 с)
  - external: TCP connect 1.1.1.1:80 (3 с) — успех = политика протекает
  - host: шлюз из /proc/net/route, TCP connect gateway:22 (3 с) — успех = политика протекает
- Классификация (rc):
  - сеть `stanok-net` отсутствует (docker network inspect) → **rc=16** (ENV-FAIL)
  - external или host открыты из контейнера → **rc=16** (политика не установлена)
  - model FAIL + хост-кросс-проверка `_fetch_server_props` OK → **rc=16** (политика блокирует модель)
  - model FAIL + сервер недоступен и хосту → **rc=20** (SERVER, не дефект политики)
  - всё сходится (model OK, external/host закрыты) → пуск продолжается
- Escape hatch: `STANOK_SKIP_NET_PREFLIGHT=1` — пропустить зонд (для хостов без docker-сети).
- Сообщения об ошибках naming: что именно отказало (network missing / policy leak / model blocked).

### R5. Opik-поле (plan §2.7)
- В summary поле `opik_traces` = `"disabled"` когда `STANOK_IN_CONTAINER=1` (мост делает
  host-Opik недоступным работнику), иначе — существующий `_opik_trace_count()`.
  Поле обязано присутствовать (не 0/null).

### R6. CLAUDE.md (machine rules)
- Формулировка «install packages» → пакеты из интернета запрещены (plan §2.8): стек проекта
  фиксирован, сети у работника нет.

## 3. Acceptance criteria

- AC1. `test_network_preflight.py`: классификация всех 5 исходов на мокнутом зонд-раннере;
  wiring в `_host_launch` (запуск до `run_sandboxed`, rc=16/20 пробрасывается);
  `opik_traces_field` unit-тесты (container → "disabled"; вне контейнера → счётчик);
  реальный docker-зонд-скрипт (skipif нет docker) на дефолтном bridge.
- AC2. `sandbox.py`: worker argv содержит `--network=stanok-net`; fresh argv — `--network=none`
  (существующий test_stage3_fresh_verify.py:51 остаётся зелёным).
- AC3. Харнесс: полный прогон обоих вариантов (Docker / без Docker) — все тесты зелёные,
  новые счётчики записаны в STATUS.md.
- AC4. `infra/stanok-net.sh` идемпотентен (двойной прогон на хосте даёт тот же iptables-вывод);
  `infra/stanok-net.service` валиден (`systemd-analyze verify` или unit-синтаксис).
- AC5. Документация: ARCHITECTURE.md (секция сети + строка цепи), README.md (env-таблица +
  установка infra), Dockerfile (комментарий про --network обновлён), exitcodes.py rc=16 строка,
  CLAUDE.md (пакеты).
- AC6. Оператору в handoff: юнит нужно установить до E1–E4 (живых запусков).

## 4. Известные оговорки (документированы, не дефекты)

- Зонд «external» vacuous-pass на хосте без интернета; «host» vacuous-pass на хосте без sshd —
  на этом хосте оба условия выполнены (интернет есть, sshd есть), оговорка для других хостов.
- Mid-run смена iptables хостом после preflight не перепроверяется (preflight = снимок до старта).
