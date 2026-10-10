# SPEC-STANOK-K8S-RUNTIME (2026-10-10)

Статус: **ПРИНЯТ оператором 2026-10-10** (решения 1–6); O1–O4 ПОДТВЕРЖДЕНЫ оператором
2026-10-10 (§11 закрыт); P0 (архивация) выполнена 2026-10-10 (`archive/research-apparmor/`,
хэши сверены с пинами). Реализация P1 — за оператором (host-side).

## 0. Цель и главный инвариант

Замена Docker/VM-раннера L2 на K8s-Job-раннер: Pod = песочница, NetworkPolicy = сетевой
рубильник. Линия AppArmor/bwrap (X1a, rev1–rev14) закрыта и архивируется (§2).

**Инвариант (не нарушается):** контракт супервизора L1 (`CLAUDE.supervisor.md`) не меняется.
Команда `stanok/launch.sh run <ticket> <label> --follow` сохраняет семантику: по завершении
`stanok/evidence/<label>/summary.json` появляется на диске хоста; rc launch.sh = итоговый
вердикт хоста; изменения кода применяются в дерево `stanok/` только при чистом вердикте.
Супервизор не знает, что под ним Kubernetes.

## 1. Решения оператора (2026-10-10) — журнал

1. **Process-level граница ПЕРЕСМОТРЕНА** (отменяет решение 2026-10-09 про bwrap netns+proxy).
   Pod-level изоляции достаточно. bwrap внутри Pod НЕ возвращается. Доступ Bash к модели из
   внутри Pod допустим; NetworkPolicy закрывает LAN и интернет.
2. **Критерий X4 ОТМЕНЁН** в прежнем виде (аудит bwrap-отказов). Истинность выполнения
   подтверждается исключительно независимым Fresh-check хоста.
3. **Власть хоста незыблема:** (а) Contract recompute — на хосте, на чистом Python/bash, при
   распаковке `changes.patch`: затронутые пути сверяются с зонами тикета и protected-файлами;
   нарушение → CONTRACT-FAIL. (б) Fresh-check — отдельный K8s Job `stanok-fresh-<label>`:
   чистое дерево + applied patch, запускается ТОЛЬКО верификатор (без Claude Code). 100%
   K8s-ready: хосту не нужен локальный Docker.
4. **rc launch.sh = код итогового вердикта хоста.** Иерархия:
   `CONTRACT-FAIL > FRESH-FAIL > WORKER-FAIL > PASS (rc=0)`. Воркеру на слово не верим.
5. **Echelon 1 (`:ro`-монтирования protected-файлов) УПРАЗДНЁН.** В Pod нет host bind mounts.
   Целостность обеспечивает post-run аудит патча хостом (единственный эшелон).
6. **Инфраструктура:** k3s — тестовый полигон; манифесты строго по стандарту K8s (без
   k3s-специфичных хаков), переносимы в multi-node. NetworkPolicy: Llama через
   `ipBlock: {cidr: 192.168.8.131/32}`; egress на Opik открыт (порт — см. O2).

## 2. Последствия для существующих линий

- **X1a (SPEC-X1A-MANAGED-PROFILES): закрыта** (зафиксировано в STATUS.md 2026-10-10).
  Артефакты rev9–rev14 (`/tmp/x1a/`, пины в SPEC-X1A) → `archive/research-apparmor/` (Phase 0).
  Модель трёх профилей остаётся ПРЕДВАРИТЕЛЬНО принятой, эмпирически не проверенной.
- **X4: закрыт** решением 2 (заменён Fresh-check как единственным доказательством).
- **X1b (upstream seccomp bake-in, R1–R3): теряет предмет** — seccomp-слой Pod даёт runtime
  (`securityContext.seccompProfile` / RuntimeClass), кастомный BPF для bwrap больше не нужен.
  Закрытие X1b — подтвердить оператору (O3).
- **S4 (stanok-net + iptables STANOK-NET + host-preflight): заменяется NetworkPolicy** на этой
  линии; Docker-era сетевой backend выводится из эксплуатации при переходе (не в момент
  написания SPEC — prod продолжает работать на Docker до green-валидации K8s-линии).
- **Echelon 1 (`host_ro_paths`)**: удалить при реализации; Echelon 2 (host recompute) — единственный.
- Живые находки остаются фактами: X1 (bwrap невозможен с обычными профилями), X4-gap
  (PASS при нуле исполненных Bash — теперь закрывается Fresh-check), bwrap 0.8.0 в образе.

## 3. Архитектура: Host-оркестратор / Pod-раннер

Разделение launch.sh (решение 5, вторая половина):

**Host-оркестратор** (`launch.sh` + `launcher/` host-ветка):
1. Гейты до запуска (без изменений): чистое дерево (rc=22), manifest pre-check (rc=13),
   run-lock (rc=21), server preflight (rc=20).
2. Транспорт (§4, решение O4): `git archive HEAD | gzip | base64` → ConfigMap
   `stanok-tree-<label>`; тикет → ConfigMap `stanok-ticket-<label>`; код раннера →
   ConfigMap `stanok-runner-<label>`.
3. Рендер манифестов (§7) → `kubectl apply` Job `stanok-job-<label>`.
4. `kubectl logs -f` до терминации Job (cap = `activeDeadlineSeconds`, §8).
5. Извлечение payload (§5), валидация патча → contract recompute (§6).
6. При чистом контракте: применение `changes.patch` к дереву `stanok/` + запуск
   `stanok-fresh-<label>` Job (§6).
7. Публикация `evidence/<label>/` (summary.json + verifier.log + contract_lock.log +
   changes.patch), cleanup Job/ConfigMap, rc = вердикт (§6).

**Pod-раннер** (внутри Pod; почти весь текущий launcher):
1. Распаковка tree-снапшота (base64 gzip tar) → рабочее дерево `/stanok-work/repo`
   (`git init` + base-коммит); чтение тикета из `/stanok/ticket/ticket.md`.
2. Запуск-гейты (SessionPlan, declared paths, zone/symlink gates — rc=13 семантика сохраняется
   внутри Pod), затем Claude Code БЕЗ собственного sandbox (`--dangerously-skip-permissions`
   или эквивалент отключения sandbox-окружения CC).
3. verify-гейт (сьюит), сбор `changes.patch` (`git diff <base-commit>`), summary.json.
4. Эмиссия payload в stdout (§5). Раннер Pod = единственный источник payload; агент payload
   не пишет.

Требование к образу: наличие `git` (`git init` + diff в Pod; в образе git есть — проверено).
Transport — tarball (§4), `changes.patch` генерируется diff-ом в Pod.

## 4. Транспорт входных данных

- Тикет: ConfigMap `stanok-ticket-<label>` (read-only mount `/stanok/ticket/`).
- Репозиторий: **решение P1 (§11 O4):** `git archive HEAD | gzip | base64` → ConfigMap
  `stanok-tree-<label>` (read-only mount `/stanok/transport/`); `git bundle` отвергнут по
  размеру (1.3 MB > порога 800 KB). Runner-код (`pod_runner.py`) — отдельный ConfigMap
  `stanok-runner-<label>` (host-side код машины не входит в транспорт дерева).
- Никаких hostPath/локальных монтирований (multi-node переносимость, решение 6).

## 5. Транспорт результатов (payload через log-stream)

Раннер в конце (на любом исходе, включая FAIL) пишет в stdout ровно один блок:

```
__STANOK_EVIDENCE_BEGIN_<NONCE>__
<base64 gzip tar: summary.json, verifier.log, contract_lock.log, changes.patch>
__STANOK_EVIDENCE_END_<NONCE>__
```

`<NONCE>` — одноразовый UUID, генерируемый HOST-оркестратором на каждый ран и передаваемый
Pod (env/ConfigMap) (решение оператора из аудита безопасности, 2026-10-10): без точного
nonce-совпадения блок не принимается — подделка payload из Bash-агента исключена.

Host-оркестратор парсит маркеры из потока `kubectl logs -f`, декодирует, раскладывает в
`evidence/<label>/`. Правила:
- Маркеры эмитит раннер-обёртка, не агент; payload — одна base64-строка.
- Принимается ровно один блок с nonce, выданным host-оркестратором этого рана; любое другое
  количество/несовпадение nonce = payload не принят → статус `missing`.
- Отсутствие/неполнота блока = прерванный запуск → статус `missing` (как сегодня), без вердикта.
- Fallback (при превышении лимитов логов): `kubectl cp` из Pod до удаления Job — реализуется на P2.

## 6. Власть хоста и вердикт

Порядок хоста (закреплён, аналог текущего snapshot→run→…→publish):

1. **Contract recompute (до применения к живому дереву):** патч применяется к scratch-копии
   дерева; сравнение с pre-run снимком protected-файлов + declared-множеством тикета:
   MODIFIED/DELETED protected → CONTRACT-FAIL; новый файл вне declared под `tests/`/`src/` →
   UNDECLARED → CONTRACT-FAIL (семантика T3-9/T3-10 сохраняется, источник diff — патч).
   **Gate патча (требование оператора, 2026-10-10):** перед `git apply` — явно отклонить
   патч, содержащий создание symlink (filemode `120000`) или путь с сегментом `..`
   (защита от записи за пределы дерева через symlink-обход). Нарушение gate = CONTRACT-FAIL.
   Живое дерево `stanok/` при CONTRACT-FAIL НЕ трогается.
2. **Fresh-check Job** `stanok-fresh-<label>`: bundle + патч (НЕ применённый к живому дереву)
   → чистое дерево внутри Job → только верификатор (`scripts/run.sh`), без агента,
   `networkPolicy: deny-all`. Результат — payload тем же протоколом. Fresh выполняется только
   при чистом контракте (семантика T3-6 §1.6).
3. **Вердикт:** `CONTRACT-FAIL > FRESH-FAIL > WORKER-FAIL > PASS`. summary.json публикуется
   нетронутым, когда ни одна host-проверка не сработала; при override — host-поля вердикта.
4. **Применение патча** к живому дереву `stanok/` — только при итоговом вердикте PASS
   (инвариант §0); при любом FAIL живое дерево не трогается.
5. **rc launch.sh** = rc вердикта. Таблица exit-кодов сохраняется (§11 O1 про rc=20).

## 7. Манифесты (`stanok/k8s/`)

- `job.yaml.tmpl` — worker Job: image по digest-пину, resources, `activeDeadlineSeconds`,
  securityContext: `runAsNonRoot: true`, `allowPrivilegeEscalation: false`,
  `capabilities.drop: ["ALL"]`, `seccompProfile: RuntimeDefault`; mount ConfigMap тикета;
  `runtimeClassName` опционален (kata в проде, стандартный runc в k3s).
- `fresh-job.yaml.tmpl` — fresh Job: тот же образ, deny-all сеть, только верификатор.
- `networkpolicy.yaml` — egress worker-Pod: kube-dns (53), `ipBlock 192.168.8.131/32` порт
  модели, Opik (O2); всё остальное — deny. Fresh-Pod: deny-all.
- Манифесты — стандартный K8s API (решение 6); рендеринг — host-оркестратор.

## 8. Жизненный цикл и CLI-поверхность

- `run --follow`: logs -f до терминации; cap 45 мин сохраняется на хосте +
  `activeDeadlineSeconds` в Job (Job-ветка: превышение → Job удаляется раннером-контроллером,
  host получает rc=124-семантику как сегодня).
- `status <label>` / `stop <label>`: отображаются на `kubectl get job` / `kubectl delete job`
  + публикация `missing` при прерванном ране.
- Run-lock: host-lock сохраняется (rc=21) + уникальность имени Job `stanok-job-<label>`.
- Cleanup: Job/ConfigMap удаляются на всех путях (аналог reaper-trap).

## 9. Сеть Pod

- Worker-Pod: NetworkPolicy §7; доступ к модели (192.168.8.131:8080) разрешён и CLI, и Bash
  (решение 1). LAN хоста и интернет — deny.
- Opik: egress открыт по решению 6; endpoint трейсинга worker-Pod — `http://<opik-svc>:8080/v1/private/otel`
  (backend), не frontend 5173 — подтверждение O2.
- KV-cache: supervisor и machine по-прежнему делят один сервер (192.168.8.131:8080) — без изменений.

## 10. Реализация: фазы и владельцы

Урок CC-217: `launcher/` — host-side, машина его не редактирует. Поэтому:

- **P0 (supervisor zone):** `archive/research-apparmor/` — копия артефактов `/tmp/x1a/`
  (профили, seccomp, probes, harnesses, скрипты, протоколы RUN1/RUN2) + пины.
- **P1 (OPERATOR host-side, red-first, как Stage 3):** host-оркестратор в `launcher/` +
  `stanok/k8s/` манифесты + Pod-раннер (перенос гейтов/verify в Pod-ветку) + payload-протокол.
- **P2 (machine tickets, acceptance-only, CC-221+):** smoke-тикеты в worktree: payload →
  evidence на хосте; патч применён; fresh Job зелёный; NetworkPolicy-изоляция (curl LAN/интернет
  → timeout; curl модели → OK). Один тикет = один сценарий приёмки.
- Валидация: локальный k3s (root-работа оператора), импорт образа по digest-пину.

## 11. Открытые пункты — ЗАКРЫТЫ (подтверждено оператором 2026-10-10)

- **O1. rc для CONTRACT-FAIL. ЗАКРЫТ:** подтверждён существующий вариант SPEC — host-issued
  CONTRACT-FAIL/FRESH-FAIL = rc=1 (DEFECT) + `probe_result: CONTRACT-FAIL|FRESH-FAIL` в
  summary.json (ветки B3/B4 протокола супервизора). rc=20 остаётся «сервер недоступен».
- **O2. Порт Opik. ЗАКРЫТ:** подтверждён backend (`:8080/v1/private/otel`), не frontend 5173.
- **O3. X1b. ЗАКРЫТ:** формально закрыт как неактуальный (Pod даёт seccomp RuntimeDefault;
  кастомный BPF для bwrap не нужен). Зафиксировано в STATUS.md.
- **O4. Transport bundle. ЗАКРЫТ как отложенный выбор:** решение принимается на P1
  (ConfigMap-base64 vs ephemeral volume; критерий — отсутствие hostPath; лимит ConfigMap
  1 MB по etcd учтён).
  **РЕШЕНИЕ P1 (2026-10-10, измерено):** `git bundle` = 1.3 MB > порога ConfigMap 800 KB →
  отвергнут. Транспорт: `git archive HEAD | gzip | base64` (снимок дерева, ~240 KB) через
  ConfigMap `stanok-tree-<label>`; история в Pod не нужна — Pod-раннер делает `git init` +
  base-коммит из распакованного дерева, реальная история остаётся на хосте. hostPath не
  используется. Реализация: `launcher/k8s.py::pack_tree/unpack_tree` (харнесс-тесты
  `launcher/tests_harness/test_k8s_transport.py`).

## 12. Критерии приёмки (DoD)

- [ ] `archive/research-apparmor/` содержит артефакты rev9–rev14 (с пинами).
- [ ] Хост не требует bwrap, кастомных AppArmor-профилей, изменения sysctl.
- [ ] `stanok/launch.sh run <ticket> <label> --follow` отрабатывает через k3s end-to-end.
- [ ] Супервизор читает `evidence/<label>/summary.json` без изменения `CLAUDE.supervisor.md`.
- [ ] Отрицательные сценарии: undeclared файл в патче → CONTRACT-FAIL, живое дерево не тронуто;
  fresh Job FAIL → FRESH-FAIL rc≠0; прерванный Pod → status `missing`, без вердикта.
- [ ] NetworkPolicy: curl LAN/интернет из worker-Pod → timeout; модель и Opik доступны;
  fresh-Pod без сети.
- [ ] Манифесты проходят `kubectl apply` на vanilla-кластере (k3s без хаков).
- [ ] Харнесс launcher (host-side) зелёный; protected-хэши согласованы с удалением Echelon 1.

## 13. Регламент запуска netpol-smoke (CC-232, оператор согласовал 2026-10-11)

`infra/netpol-smoke.sh` — живой кластерный прогон сетевой политики (probe-Pod'ы,
make-before-break cutover, DNS blackout, paired SSH, ingress). Он дополняет
статические проверки: харнесс `test_k8s_manifests.py` пинит манифесты,
pre-flight гейт (CC-232, `launcher/k8s.py::_preflight_cluster`) перед каждым
запуском проверяет доступность кластера и совпадение манифестов с контрактом —
но ни то, ни другое не измеряет поведение CNI/политики в живом кластере.

**Триггеры (обязательный запуск):**
1. изменение `k8s/networkpolicy.yaml.tmpl` или `launcher/netpol.py` (до и после
   cutover — smoke сам выполняет make-before-break);
2. обновление k3s / CNI (flannel) / ноды кластера;
3. любой сетевой дефект прогона (класс CC-225: ConnectionRefused/timeout Pod→Opik)
   — до и после фикса;
4. перед production-запуском после длительного простоя кластера (> 1 недели).

**Периодичность:** еженедельно, cron-запись на хосте оператора (установка —
действие оператора; супервизор cron не устанавливает):

```cron
# crontab -e (k3s-хост): понедельник 06:00
0 6 * * 1 KUBECONFIG=$HOME/.kube/config STANOK_SERVER_URL=http://192.168.8.131:8080 \
  /home/hermes/darkcast/stanok/infra/netpol-smoke.sh
# опционально: STANOK_LAN_PEER=<ssh-хост-LAN> включает 2 внешних host-exposure
# проверки; без него они честно помечаются SKIP (не PASS).
```

**Вердикт и доказательства:** exit 0 = все hard-проверки совпали; 1 = mismatch
(дефект политики); 2 = preflight/cutover (инфраструктура). Доказательства —
`stanok/evidence/netpol-<ts>/` (results.txt, applied манифест, sha256,
versioned имена + revision). Строка вердикта строго динамическая:
`N/N hard checks passed (M external SKIPPED, K INFO)`.
