# SPEC — X1a: bwrap + managed профили (целевая архитектура; решение оператора 2026-10-09)

Статус: принято решение оператора. Вариант 1 (`bwrap` + управляемые профили) — целевая
архитектура. Вариант 2 (`sandbox.enabled:false`, только контейнер) — ОТКЛОНЁН для текущих
требований. Ничего в production не менялось; экспериментальные профили в ядро не загружены.

## 0. Инвариант сетевой изоляции (формальное требование, из-за которого существует bwrap)

**Claude Code (CLI процесса) обращается к модели; команды Bash, запущенные агентом, не
получают прямого доступа к модели (192.168.8.131) и Opik.**

Docker не различает родительский и дочерний процессы на уровне netns: если контейнеру
разрешён доступ к модели, `curl` из Bash получает тот же путь. Единственный механизм в
нашей связке, разделяющий CLI и его Bash, — process-level граница: отдельный netns
вложенного bwrap (`--unshare-net`) + socat-мост к in-process прокси с allowedDomains
(`NOTE-CLI-SANDBOX-2026-10-09.md` §3). Отсюда: вариант 2 не эквивалентен варианту 1 по
сетевой модели угроз и приниматься может только при формальном пересмотре требований.

## 1. Разделение механизмов (не взаимозаменяемы, дополняют)

| Механизм | За что отвечает |
|---|---|
| Docker seccomp (внешний) | разрешить операции запуска `bwrap`; заблокировать опасные варианты создания namespaces (условная обработка `clone3` — см. R4.3) |
| AppArmor профили (внешние, managed) | разрешить mount-операции самому `bwrap` (setup-фаза), не передавая разрешения недоверенным командам (exec-переход `px → stanok-sandbox`) |
| Встроенный seccomp Claude Code (`apply-seccomp` + `unix-block.bpf`) | блокировать `AF_UNIX` и связанные `io_uring`-обходы у команд Bash |

Аудит полномочий (CONTEXT 2026-10-09): mount-полномочия уже ограничены capabilities
(только bwrap setup-фаза). Внешние профили и встроенный seccomp — defense-in-depth поверх
этого; ни один не заменяет другой.

## 2. Требования

R1. **Штатный seccomp из upstream, без самописного BPF.** Запечь в образ `apply-seccomp`
    + `unix-block.bpf` из зафиксированной версии `@anthropic-ai/sandbox-runtime`
    (пиновка: версия upstream + SHA256 бинарников в репозитории; bundled cli.js 2.1.88
    версии пакета не несёт — пин выбираем сами, поведение сверяем эмпирически).
    Указать `sandbox.seccomp.bpfPath/applyPath` в settings. НЕ создавать mount-only BPF
    (он потерял бы защиту Unix-сокетов).
    Примечание: поиск `vendor/seccomp/{x64,arm64}/` относительно каталога cli.js тоже
    работает без настроек, но явный путь + SHA — воспроизводимее.

R2. **Наличие и фактическое применение фильтра — обязательная проверка запуска.**
    Preflight лаунчера: бинарники присутствуют; probe-запуск с `SRT_DEBUG=1` подтверждает
    применение («[SeccompFilter] Using pre-generated BPF filter», «Wrapped command with
    bwrap (… seccomp(unix-block))»). Отсутствие/отказ → ENV-FAIL (класс rc=16), не
    молчаливая деградация (сейчас cli.js при отсутствии бинарников только warn'ит).

R3. **Эмпирика из настоящей Bash-песочницы:** блокировка `AF_UNIX` (создание unix-сокета)
    и связанных `io_uring`-вызовов; при этом штатный сетевой мост (proxy через
    bound-сокет) сохраняет работоспособность. Конструкция `qC_` поднимает bridge-socat ДО
    применения фильтра (фильтр — только на команду пользователя) — это ожидаемое поведение,
    но проверяется живым тестом, не по коду.

R4. **X1a внешние профили: bwrap без `unconfined`.** До загрузки профиля — проверка
    модели полномочий (расширение уже сделанного аудита):
    1. Из реальной Bash-песочницы: `clone(CLONE_NEWUSER|CLONE_NEWNS)` одним вызовом,
       `clone3` с теми же флагами, `setns`, вложенный `bwrap` — не ограничиваться
       отдельными `unshare`.
    2. **R4.2 — AppArmor-переходы: одноразовый тест с временными профилями
       (протокол подтверждён оператором 2026-10-09).** Реальные переходы для `bwrap`,
       Bash и исполняемых файлов команд: ни один путь выполнения не обходит
       `stanok-sandbox`; расширенные mount-разрешения не остаются у недоверенных
       процессов. Протокол (артефакты `/tmp/x1a/`; запуск оператором только
       проверенной root-копии `/run/x1a-test/x1a-test.sh`, см. пин хэша ниже):
       - уникальные test-имена `stanok-bwrap-x1a-test` / `stanok-sandbox-x1a-test`;
         предпроверка: имён нет в ядре (`/sys/kernel/security/apparmor/profiles`) и нет
         ссылок в `/etc/apparmor.d`;
       - загрузка ДО старта контейнера: `apparmor_parser -a` (ADD; в apparmor_parser
         4.0.1 ADD — дефолт/`-a`, `-W` — это `--write-cache`, `-r` — replace; `-K` —
         отключение кэша парсера, постоянству политики НЕ управляет: временность
         обеспечивается тем, что профили загружаются только в ядро, не устанавливаются
         в `/etc/apparmor.d` и удаляются по окончании теста); профиль существует в
         ядре до `docker run --security-opt apparmor=stanok-bwrap-x1a-test`;
       - изолированный тест-контейнер (`--rm`, `--network=none`, cap-drop=ALL,
         no-new-privileges, seccomp=`v-cli3.json`, `--user 1000:1000`, образ
         `stanok-machine:latest`); `docker-default` не менять, Docker не перезапускать,
         production-контейнеры не трогать;
       - **пин identity образа (rev4, обзор #3):** `docker image inspect` зафиксировал
         ID `sha256:913ad405b48948ab3c31d0222774163a65ad083b0c3541d8303be39380f5b15c`;
         скрипт сверяет `docker image inspect "$IMAGE" --format '{{.Id}}'` с этим пином
         до первого запуска контейнера — несовпадение ID = abort (профиль даёт контейнеру
         mount-операции, identity образа обязана быть точной); **все три `docker run`
         используют зафиксированный ID напрямую, а не изменяемый тег (rev7, обзор #6)**;
       - **свобода имён + scoped-очистка (rev4, обзор #3):** до запуска проверяется,
         что имена `stanok-x1a-a7-strict` / `stanok-x1a-a7-weaker` / `stanok-x1a-a8`
         не заняты (`docker ps -a`); каждый контейнер помечается `--label
         stanok-x1a-run=<uuid>` (uuid из `/proc/sys/kernel/random/uuid`); очистка
         удаляет ТОЛЬКО контейнеры с этой меткой данного запуска — чужие контейнеры
         не удаляются никогда;
       - **схема переходов профиля (rev5, обзор #4 — блокирующая проблема):** широких
         правил (`/usr/bin/* px → …`) в профиле нет и не будет. Пути проверены в образе
         (2026-10-10): `bwrap` = `/usr/bin/bwrap` (обычный файл), `/bin/sh` резолвится
         в `/usr/bin/dash` (фактический переход песочничной оболочки — по правилу
         `/usr/bin/dash`), `python3` = `/usr/bin/python3` → `python3.11`. `bwrap` пинится
         ЯВНО: в entry-профиле `/usr/bin/bwrap px → stanok-bwrap-x1a-test` (bwrap из
         entry остаётся в mount-capable профиле всю setup-фазу, поведение не зависит от
         «нет правила → наследуй»); в sandbox-профиле `/usr/bin/bwrap px →
         stanok-sandbox-x1a-test` (вложенный bwrap из песочницы остаётся confined,
         mount запрещён). **change_profile удалён из обоих профилей (rev6, обзор #5):**
         назначение профиля при старте контейнера проверяется против текущего
         (host-side) профиля до смены, а не против целевого (прецедент: docker-default
         не содержит change_profile); px-переходы права change_profile не требуют;
         явных смен профиля тест не выполняет. **RUN1 (2026-10-10, rev8) FAIL на
         A7-strict:** kernel audit DENIED `operation="mount" name="/" comm="bwrap"
         flags="rw, silent, rslave"` — bwrap `make_propagation_slave()`
         (`mount(NULL,"/",NULL,MS_SILENT|MS_SLAVE|MS_REC,NULL)`) не покрыт правилом
         `remount /` (диагностика: `X1A-R4.2-RUN1-2026-10-10.md`). **rev9:** добавлено
         узкое exact-match правило `mount options=(rw, silent, rslave) -> /,` (только
         на `/`, общего `mount` нет; токены `silent`/`rslave` валидны по apparmor.d(5)).
         **RUN2 (2026-10-10, rev9) FAIL на A7-strict:** kernel audit DENIED
         `info="failed srcname match" name="/tmp/" comm="bwrap" fstype="tmpfs"
         srcname="tmpfs" flags="rw, nosuid, nodev"` — правило `mount fstype=tmpfs /tmp,`
         по грамматике apparmor.d(5) (`MOUNT = [QUALIFIERS] [SOURCE FILEGLOB] ['->'
         [MOUNTPOINT FILEGLOB]]`) трактует путь без `->` как ИСТОЧНИК, а не точку
         монтирования (диагностика: `X1A-R4.2-RUN2-2026-10-10.md`; rslave-правило
         rev9 сработало — bwrap дошёл до tmpfs). **rev10 (обзор оператора #9):**
         четыре fstype-правила переписаны в `mount fstype=X -> <mountpoint>,`
         (/tmp, /newroot/dev, /newroot/dev/pts, /newroot/proc); remount/umount-правила
         не изменены (грамматика REMOUNT/UMOUNT принимает MOUNTPOINT напрямую, без
         `->`); разрешения не расширены. **rev11 (обзор оператора #10):**
         незаданные условия mount-правил совпадают с ЛЮБЫМИ значениями
         (apparmor.d(5)), поэтому четыре fstype-правила ужены до exact-форм
         `mount fstype=X options=(…) <srcname> -> <mountpoint>/,` по фактическим
         вызовам bwrap 0.8.0 (образ содержит bubblewrap 0.8.0, `bwrap --version`
         подтверждён; bubblewrap.c: root tmpfs `MS_NODEV|MS_NOSUID` :2554,
         --tmpfs `MS_NOSUID|MS_NODEV` :986, devpts `MS_NOSUID|MS_NOEXEC` :991,
         proc `MS_NOSUID|MS_NOEXEC|MS_NODEV` :971; та же форма в опубликованной
         абстракции apparmor.d `abstractions/bwrap`, roddhjav/apparmor.d).
         Расширения нет: те же mountpoint, меньше допустимых вариантов.
         **rev12 (обзор оператора #11): полный аудит mount-правил по фактическому
         исходнику bubblewrap v0.8.0 (bubblewrap.c, bind-mount.c) и kernel v6.8
         security/apparmor/mount.c.** Кодирование флагов ядром (`audit_mnt_flags`):
         `MS_BIND|MS_REC` → токен `rbind` (никогда `bind`+`rbind` вместе); `MS_BIND`
         отдельно → `bind`; `MS_REC|MS_PRIVATE` → `rprivate`; `MS_REC|MS_SLAVE` →
         `rslave`; `MS_SILENT` → `silent`; `rw` присутствует всегда. Маски медиации:
         `aa_bind_mount()` обрезает флаги до `MS_REC|MS_BIND` → каждый ПЕРВИЧНЫЙ bind
         медиится как `options=(rw, rbind)` (silent/ro/nosuid отбрасываются);
         `aa_mount_change_type()` обрезает до `MS_REC|MS_SILENT|MS_SHARED|MS_PRIVATE|
         MS_SLAVE|MS_UNBINDABLE`, devname=NULL → change-type операции — это `mount`
         -правила `options=(rw, silent, rprivate/rslave)` без srcname; `aa_remount()`
         передаёт полные флаги → remount-правила НЕ содержат options=. Все bind bwrap
         рекурсивны (`PRIV_SEP_OP_BIND_MOUNT` всегда `BIND_RECURSIVE`, bubblewrap.c:964)
         → голый `bind` в аудите не появляется: правила rev11 `options=(bind)`,
         `options=(bind,rbind)`, `options=(bind,ro)` — мёртвые exact-match несовпадения,
         удалены (не расширены). Точечные исправления по строкам bwrap: self-bind newroot
         (`main :2568`, CWD=/tmp) → `mount options=(rw rbind) /tmp/newroot/ ->
         /tmp/newroot/`; oldroot make-rprivate (`main :2622`) → change-type
         `mount options=(rw, silent, rprivate) -> /oldroot/` (rev11 `remount /oldroot`
         — мёртвое, удалено); umount после второго pivot (`main :2651`, umount2("."))
         → `umount /` (отсутствовало в rev11); первичные binds root-bind/proc-covers
         (`setup_newroot :1058-1113`) → `mount options=(rw rbind) /oldroot/ ->
         /newroot/` + `/oldroot/** -> /newroot/**` и `/newroot/proc/**` (ro/nosuid
         применяются remount-шагом,
         bind-mount.c:452,472); remount-шаг bind_mount → `remount /newroot/{,**}`
         без options= (`{,**}` матчит сам /newroot/; rev11 `remount /` — мёртвое,
         удалено). Точки монтирования каталогов в аудите с завершающим `/`
         (`aa_path_name`, PATH_IS_DIR) — правила используют слэш. **Новый
         отрицательный тест прямого clone() из entry-профиля (A8, rev12):** E1 —
         прямой mount tmpfs без нового namespace → ожидаем EACCES (AppArmor медирует
         до проверки capabilities); E3 — `clone(CLONE_NEWUSER|CLONE_NEWNS|CLONE_NEWPID|
         SIGCHLD = 805437457)` (ровно разрешённая комбинация закреплённого seccomp
         v-cli3.json, exact-match arg0): ребёнок получает полный caps в новом userns
         и наследует entry-профиль (нет exec-перехода); внутри: E3-DENY mount tmpfs
         в /tmp/escape-test (нет правила) → EACCES; E3-CONTROL mount tmpfs в /tmp
         (entry-правило разрешает) → OK (доказательство наличия capability: DENY
         = AppArmor, не capabilities); E3-PROFILE /proc/self/attr/current → entry.
         Скрипт требует `CLONE-TEST: PASS`; любое неожиданное OK на DENY или
         unconfined профиль = FAIL теста, без автоматического расширения разрешений.
         Статическая проверка mount-строк расширена: отвергает также голый токен
         `bind` внутри options= (ядро медирует рекурсивные bind как rbind).
         Текущий профиль: SHA-256 =
         `f6c9abef5ee8c6ceb23e7083879bc57503e2d76088fe8b8351d54dbb4d6b5b88`
         (`apparmor_parser -Q -K` зелёный; предыдущие пины `6f284022…`, `06fc2e51…`, `128901bd…`, `59ada146…`, `3db1cc24…`, `0dea2834…` отменены);
         **rev12 НЕ загружен (обзор оператора #12): модель полномочий отвергнута.**
         Замечание: Docker назначает entry-профиль контейнеру целиком, а
         `/usr/bin/bwrap px → тот же профиль` не создаёт границы между Claude Code и
         setup-процессом bwrap: процессы, не выполнившие переход, остаются
         mount-capable; E3 доказывает только ограничение по путям, не «монтировать
         может только bwrap». **rev13 (модель, подготовлена по обзору #12; загрузка
         только после одобрения оператора):** три профиля — `stanok-worker-x1a-test`
         (назначается контейнеру; `deny mount, deny remount, deny umount,
         deny pivot_root,`; единственный путь к mount-правам — exact-переход
         `/usr/bin/bwrap px → stanok-bwrap-x1a-test`), `stanok-bwrap-x1a-test`
         (mount-capable, ровно отаудированный rev12 mount-блок + CATCH-ALL
         `/** px → stanok-sandbox-x1a-test`: любая команда bwrap теряет mount-права;
         без catch-all `bwrap <binary>` наследовал бы mount-capable профиль — та же
         дыра, что E3 показал в rev12), `stanok-sandbox-x1a-test` (как rev12 +
         `deny remount, deny pivot_root`; `/usr/bin/bwrap px → sandbox`: недоверенный
         процесс не переходит в mount-capable профиль через bwrap). Основание границы:
         AppArmor-профиль наследуется при clone()/fork() и меняется только exec'ом
         (инвариант ядра) → worker и его clone-потомки не монтируют; mount-capable
         профиль достижим только exec'ом закреплённого пути `/usr/bin/bwrap` из
         worker. Ограничения парсера (проверено apparmor_parser 4.0.1): ключевое
         `file,` конфликтует с glob-px («merged rule with conflicting x modifiers»),
         abstractions/base (mrixwlk) конфликтует с glob без execute; поэтому
         bwrap-профиль без base/`file,`: `/** mrwlk,` (все file-права без execute;
         `a` с `w` взаимоисключающи) + catch-all px; worker/sandbox остаются с
         base+`file,` (exact-px валидны). `deny remount`/`deny pivot_root` парсятся.
         Черновик профиля: `/tmp/x1a/rev13/stanok-x1a-test.apparmor` SHA-256 =
         `117302ab501d9a04af0c22c9af0d12d1291b1e3072257f6b862f23ab1ea1e018`
         (`apparmor_parser -Q -K` зелёный; ДRAFT, финальный пин — после одобрения).
         Матрица отрицательных тестов (полный путь исполнения, реализация — после
         одобрения модели): W1 worker прямой mount → EACCES; W2 worker clone(805437457)
         → профиль ребёнка = worker, mount → EACCES (clone не даёт mount-прав);
         W2b ребёнок W2 исполняет `/usr/bin/bwrap` → успех (capability есть,
         mount-права только через exec-переход); W3 копия бинаря в `/tmp/mybwrap` из
         worker → наследует worker, setup FAIL (переход привязан к точному пути);
         W4 (probe P8) sandbox → bwrap → остаётся sandbox, setup FAIL; W5 (probe P10)
         sandbox clone → профиль sandbox, mount EACCES; W6 (probe P11) `bwrap python3`
         (не-shell) → python3 в sandbox-профиле (доказательство catch-all).
         Дефект probe, исправляется в rev13: P2/P4 ждут EPERM(1), но AppArmor
         `deny mount` медирует до проверки capabilities → EACCES(13).
         **Обзор оператора #13 (2026-10-10): rev13-черновик не одобрен; блокер —
         ptrace между stanok-bwrap и stanok-sandbox (унаследован из rev12).**
         AppArmor проверяет обе стороны (trace у tracer, tracedby у target);
         /proc/<pid>/mem и process_vm_readv медиуются теми же ptrace read/readby
         правами; при enableWeakerNestedSandbox=true песочница видит процессы
         исходного /proc — mount-capable процесс не обязан быть невидимым для
         недоверенных команд. Закрыто (rev13b): ВСЕ межпрофильные ptrace-правила
         удалены из трёх профилей; оставлен только ptrace внутри одного профиля
         (нужен доверенным командам для ptrace собственных потомков — control C1
         теста W7). Реальный путь исполнения (worker → exec bwrap → exec команды;
         bwrap setup) ptrace между профилями не использует — удалено без потерь.
         **Тест W7 реализован** (`/tmp/x1a/rev13/w7-probe.py`, пин
         `e22d0314143774166c71dfc0332defd5eda6c7085da46c492a741e1088a0baeb`;
         запускается скриптом как команда песочницы в A7-strict и A7-weaker):
         цель — PID1, в обоих режимах это процесс bwrap (strict: PID1 свежего
         pidns/procfs; weaker: PID1 контейнера = bwrap, docker запускает bwrap как
         команду контейнера), проверяется `comm=bwrap`; попытки PTRACE_ATTACH(1),
         чтение `/proc/1/mem`, `process_vm_readv` — ожидаемый отказ; control C1:
         PTRACE_ATTACH к собственному ребёнку probe (fork, тот же профиль) — обязан
         быть РАЗРЕШЁН (доказательство, что отказ специфичен межпрофильному каналу).
         **Атрибуция (задача 3 обзора #13):** seccomp v-cli3.json — `ptrace`,
         `process_vm_readv`, `process_vm_writev` ALLOW без условий (строки 480-490,
         minKernel 4.8; проверено 2026-10-10) → тест не вакуумный по seccomp;
         `fork`/`kill`/`waitpid` ALLOW (C1 исполним); host Yama `ptrace_scope=1`
         независимо от AppArmor запретил бы non-descendant ATTACH → скрипт
         выставляет 0 ТОЛЬКО на окно W7 и восстанавливает в cleanup(); uid общий
         (1000) → DAC пропускает; с PASS control C1 единственный оставшийся
         механизм запрета — AppArmor; записи аудита AppArmor (dmesg, grep ptrace)
         собираются как подтверждение (не gate).
         Новый профиль (rev13b, `apparmor_parser -Q -K` зелёный, mcheck rc=0):
         `/tmp/x1a/rev13/stanok-x1a-test.apparmor` SHA-256 =
         `420505ed30ec7f6df094a27f217dc677574cc0d37cd8ee3287ae6f71c5b3f129`
         (черновик `117302ab…` отменён). Скрипт rev13 (ENTRY=worker, загрузка/
         проверка трёх профилей, W7 в обоих режимах, Yama-окно; A8/harness отложен
         до раунда реализации harness по последовательности обзора #13):
         `/tmp/x1a/x1a-test.sh` SHA-256 =
         `f8a6b8c823e28d022b28523304797203c9b533341525dd6ab41b5e578dfff29f`
         (пин `7aa177d0…` отменён). Порядок запуска rev13: A7-strict → A7-weaker →
         W7-strict → W7-weaker. **Загрузка в ядро — только после успешного W7**
         (обзор #13); описание A8-strict ниже остаётся историческим (rev12).
         **Обзор оператора #14 (2026-10-10): rev13b архитектурно принят к экспериментальной
         проверке (модель трёх профилей ПРЕДВАРИТЕЛЬНО принята), но запуск W7 на основном
         хосте ЗАПРЕЩЁН:** скрипт временно меняет глобальный sysctl
         `kernel.yama.ptrace_scope` 1→0 — это ослабляет защиту всего хоста (процессы одного
         UID могут ptrace подключаться к dumpable-процессам, включая SSH-агент), а `trap`
         не гарантирует восстановления после SIGKILL/зависания/аварии. Требование: запустить
         эксперимент в одноразовой Linux VM, выполнить W1–W7, уничтожить VM. Профили НЕ
         переделывать (пин `420505ed…` неизменен). До зелёных W-тестов не считается
         доказанным, что mount-полномочия получает только bwrap.
         **rev14 (VM-изоляция + полная W-матрица, без изменения профилей):**
         - VM: облачный образ Ubuntu 24.04 (noble) — ядро 6.8 + apparmor_parser 4.0.1,
           т.е. те же версии, на которых закреплён аудит mount-правил и ограничения парсера.
           `noble-server-cloudimg-amd64.img` (625 612 288 байт) SHA-256 =
           `6a81c37564db9b1ee84e141922625e1d7c5b389b99bb3c572e0243607d5bb4d2` (скачан и
           запинен 2026-10-10; хранится в `/var/tmp/x1a-vm/`, вне staging `/run`).
           LXC/nspawn непригодны: Yama — глобальный sysctl, не namespaced → нужно реальное
           ядро VM. Pinned-образ передаётся `docker save/load` (content-addressed; ID
           `913ad405…` верифицируется внутри VM до первого контейнера). Хост-предпосылки
           (root, оператор): `apt install qemu-system-x86 qemu-utils cloud-image-utils`.
           Временная загрузка тестовых профилей в ядро VM безупречна по обзору #13:
           ядро VM одноразовое и уничтожается вместе с VM.
         - **ФАКТ о версии (проверено 2026-10-10):** pinned-образ содержит bubblewrap
           **0.8.0** (`docker run <ID> bwrap --version`) — ровно базис аудита mount-правил;
           хостовый bwrap 0.9.0 неучастен: профиль опосредует КОНТЕЙНЕРНЫЙ `/usr/bin/bwrap`.
           Расхождение «аудит 0.8.0 vs хостовый 0.9.0» закрыто: тестируемый бинарь — из образа.
         - Оркестратор `/tmp/x1a/vm-run.sh` SHA-256 =
           `ed4b2d58902cd194071ea557e1e98d5fdb41d5308097e95c935ba4fdfd857ef6`:
           сверяет собственный хэш (строка 2 `pinned.sha256`) и хэш тест-скрипта (строка 1),
           верифицирует все входы по пинам, поднимает VM (qemu `-enable-kvm`, 2 vCPU, 2048MB;
           overlay 12G поверх pinned-базы 3.5G + growpart/resize2fs в госте; cloud-init NoCloud:
           ssh-ключ, пакеты docker.io + cloud-guest-utils), ждёт ssh (≤300 с), preflight внутри
           VM (AppArmor, apparmor_parser, Yama, docker), передаёт входы + image.tar
           (хэши сверяются повторно ВНУТРИ VM), стейджит `/run/x1a-test` внутри VM (root 0500 +
           pinned.sha256), выполняет `sudo /bin/sh /run/x1a-test/x1a-test.sh` ВНУТРИ VM
           (Yama-окно локально для VM), экспортирует результаты в `/tmp/x1a/vm-results-<ts>/`,
           уничтожает VM (trap на всех путях выхода; база и результаты сохраняются).
           Запуск: оператор стейджит `vm-run.sh` + `x1a-test.sh` + `pinned.sha256` (2 строки:
           скрипт, оркестратор) в `/run/x1a-test` и выполняет
           `sudo /bin/sh /run/x1a-test/vm-run.sh`.
         - **W-матрица реализована** (модель предварительно принята; W1–W6 добавлены в скрипт,
           один контейнер, worker-entry): `w-harness.py` — H-P (собственный профиль=worker),
           W1 прямой mount → EACCES (AppArmor опосредует sb_mount ДО проверки capability;
           EPERM НЕ доказывал бы AppArmor), W2 clone(805437457) — потомок наследует worker и
           mount EACCES при наличии caps в новом userns, W2b fork-потомок exec
           `/usr/bin/bwrap` → strict-сборка OK (единственный путь к mount-правам), W3 копия
           bwrap в `/tmp/mybwrap` exec из worker → наследует worker → сборка FAIL,
           W6 bwrap exec python3 напрямую → catch-all → sandbox; SHA-256 =
           `ee0e886dd8927ad24f711817eabaaaa535fb852c83708a52acfb1f4f00539ff5`.
           `w-probe.py` — песочничная сторона: P8=W4 (вложенный bwrap из sandbox остаётся
           confined), P10=W5 (clone-потомок наследует sandbox + mount EACCES); исправленные
           латентные дефекты отложенного a8-probe.py: P2/P4 ждут EACCES(13), а не EPERM(1);
           P5/P6 гейтятся по факту отказа (значение seccomp-ERRNO — деталь seccomp, не
           проверяемое свойство); SHA-256 = `7164704e62938046571c257d30d91575d8dfce4d9e6f63bb1aff9dc38c343415`.
           Скрипт rev14 `/tmp/x1a/x1a-test.sh` SHA-256 =
           `63f694755d67495a24af4c29bc14021795c1778c82f4ad277c128744a0115260`
           (пин `f8a6b8c8…` (rev13b) отменён). Порядок: A7-strict → A7-weaker → W-matrix
           (W1–W6) → Yama-окно → W7-strict → W7-weaker → уничтожение VM.
       - защищённый staging: сам скрипт пинится ВНЕШНИМ хэшем (этот документ):
         `x1a-test.sh` SHA-256 = `63f694755d67495a24af4c29bc14021795c1778c82f4ad277c128744a0115260`
         (rev14, обзор #14: VM-изоляция + W-матрица; пин `f8a6b8c8…` (rev13b) отменён;
         оркестратор `vm-run.sh` = `ed4b2d58…`, pinned.sha256 = 2 строки: скрипт, оркестратор);
         (rev12: пины профиля/harness обновлены на f6c9abef…/8c270d8f… + комментарий rev12;
         статическая проверка семантики mount-правил расширена (rev12): отвергает строку
         `mount …` без `->`, без options= и с голым токеном `bind` внутри options=
         (remount/umount/comments не матчатся), abort до загрузки профилей; проверена
         независимо под `sh` (фактический интерпретатор запуска): rev12-профиль проходит
         (rc=0), синтетический fixture с дефектами rev11 (`options=(bind)`,
         `options=(bind,rbind)`, отсутствие options=, `options=(bind,ro)`) даёт rc=1,
         корректные правила rev12 (`options=(rw rbind)`, `remount /newroot/{,**}`,
         `umount /`) не флагуются; A8-проверка скрипта теперь требует и
         `CLONE-TEST: PASS`; предыдущие пины `06b131a4…`, `77fa3c58…`, `13ffdb53…`, `449ae4db…`, `1f73adf3…`, `5dab9bbd…`, `c58eaccea…`, `9b488bcb…`, `50b6186a…` отменены);
         входной файл `a8-harness.py` SHA-256 =
         `8c270d8feccb87af3643d2101eadadd905dd21b27f2558724f598c7db70915fc`
         (rev12: добавлен clone()-тест E1/E3 по описанию выше; предыдущий пин
         `c596c559…` (rev8) отменён);
         оператор сверяет `/tmp/x1a/x1a-test.sh`, копирует проверенный файл в
         `/run/x1a-test/x1a-test.sh` (root:root, каталог 0700, скрипт 0500),
         записывает пин в root-файл `/run/x1a-test/pinned.sha256`, сверяет хэш
         root-копии (`sudo sha256sum /run/x1a-test/x1a-test.sh` = пин) и запускает
         только эту копию (скрипт отказывается исполняться с другого пути; при
         запуске сам перечитывает `pinned.sha256` и сверяет собственный хэш —
         несоответствие = abort);
       - входные файлы (профиль, seccomp, probe, harness) проверяются по закреплённым в скрипте
         SHA-256 (несовпадение → abort), копируются в root-подкаталог
         `/run/x1a-test/in` (0700), хэши сверяются повторно, все этапы используют
         только staged-пути; результаты — только в root-подкаталоге
         `/run/x1a-test/results` (0700, вне user-writable родителей); **root не пишет
         в user-writable каталоги (rev7, обзор #6):** автоматическая root-публикация
         удалена (TOCTOU: пользователь мог подменить PUB-подкаталог между mkdir и cp);
         **доступ к результатам (rev8, обзор #7):** `chmod -R a+rX` одних результатов
         недостаточно — родитель `/run/x1a-test` (0700) блокировал бы проход; в cleanup()
         (выполняется и на путях FAIL) `$BASE` получает ТОЛЬКО проход (`chmod a+x`,
         каталог остаётся нелистуемым: root-скрипт 0500, пин и staging 0700 не
         раскрываются), чтение открывается только для `results/`; экспорт в
         пользовательский каталог — отдельная команда БЕЗ root, выполняемая
         оператором после теста;
       - порядок (два режима не смешивать): **A7-strict** (строгий режим,
         `enableWeakerNestedSandbox=false`: bwrap с `--proc /proc`; профиль обязан
         разрешать `mount fstype=proc /newroot/proc` и ro-bind-«крышки»
         `/newroot/proc/{sys,sysrq-trigger,irq,bus}` — bubblewrap.c:1121,1247-1285;
         внутренний `/bin/sh` обязан быть в `stanok-sandbox-x1a-test` — px-переход)
         → **A7-weaker** (отдельный тест текущего prod-режима `true`: без `--proc`)
         → **A8-strict** (внешний процесс — тестовый HARNESS `a8-harness.py` на python3:
         в entry-профиле нет px-правила для python3 → harness остаётся в entry-профиле
         (наследуется; проверяется эмпирически, а не предполагается: сначала печатает
         собственный профиль — обязан быть `stanok-bwrap-x1a-test`: доказательство, что
         `bwrap` вызван из mount-capable профиля). `/bin/sh` как внешний процесс НЕ
         используется (rev8, обзор #7): все шеллы имеют px → sandbox и не могли бы
         исполнить mount-capable bwrap — заявленный в rev7 OUTER-PROFILE противоречил
         собственной модели переходов; профиль из-за этого не менялся); далее
         `/tmp/x1a/a8-probe.py` внутри
         песочницы строгого режима:
         фактический профиль Bash; `mount` → EPERM; `unshare(NEWUSER)` разрешён, но
         mount после него по-прежнему EPERM — вложенный userns не даёт расширенных
         mount-прав; `unshare(NEWUSER|NEWNS)`, `clone3`, `setns`, вложенный bwrap —
         отказ; в строгом режиме outer mount ns недосяжен песочнице — свежий procfs,
         фиксируется как более сильное свойство; python3 наследует sandbox-профиль,
         обхода нет). Любой FAIL → стоп, без автоматического расширения разрешений;
       - очистка: trap (`EXIT`/`INT`/`TERM`) устанавливается ДО первой попытки загрузки;
         контейнеры этого запуска удалены по метке `stanok-x1a-run=<uuid>` (не по имени),
         оба профиля сняты `apparmor_parser -R` и проверено их
         исчезновение из loaded policy; оставшийся загруженный профиль = ошибка всего
         эксперимента (ненулевой итог); логи и результаты — в `/run/x1a-test/results/`
         (доступ открывается в cleanup(): `$BASE` traversal-only, `results/` читаем;
         экспорт — отдельная команда без root).
       Managed backend (R6) — только после зелёного теста; при FAIL сначала доработка
       профилей.
    3. Подтверждение, что seccomp и AppArmor не отключены: ограничения проверяются
       фактическими вызовами и системными журналами. Docker seccomp допускает условную
       обработку `clone3` → безопасность не считается доказанной по одним `unshare`-тестам.

R5. **X4 (условие production-приёмки):** любой отказ песочницы на отдельном Bash-вызове
    (`bwrap: …` в tool-результате) и отсутствие/отказ `apply-seccomp` → ENV-FAIL,
    даже если внешний verifier завершился с rc=0. Подтверждённый gap: прогон `x1` дал
    PASS при 12 отказах Bash и нуле исполненных песочничных команд.

R6. **Managed backend профилей — только после успешных R4-тестов.** Версионируемый
    компонент коробки (паттерн `infra/stanok-net.{sh,service}`, S4): профиль в
    репозитории, проверка совместимости, идемпотентная установка, preflight (профиль
    загружен → иначе отказ запуска), обновление, удаление. Root — один раз при установке;
    запуск worker профили не загружает.

R7. **Ограничения на время эксперимента:** экспериментальные профили в ядро не загружать
    (кроме test-загрузки по R4.2 с разрешения оператора); production не менять;
    Compose+Envoy (SPEC-NETWORK-PROD R3–R6) не начинать.

## 3. Acceptance

- [ ] Образ содержит `apply-seccomp` + `unix-block.bpf` (пин версии + SHA256 в репозитории).
- [ ] Preflight: отсутствие бинарников → ENV-FAIL (тест лаунчера, red-first).
- [ ] Живой тест из песочницы: AF_UNIX/io_uring заблокированы; proxy-мост работает.
- [ ] R4.1–R4.3: пробы clone/clone3/setns/nested-bwrap + переходы AppArmor зафиксированы
      в evidence/протоколе; ни один путь не обходит stanok-sandbox.
- [ ] bwrap работает при seccomp=custom + apparmor=<managed> (без unconfined) — прогон
      гейта (форма X1) зелёный: песочничные Bash исполнены, verifier PASS.
- [ ] X4: per-call bwrap-отказ → ENV-FAIL (тест лаунчера, red-first).
- [ ] Managed backend: установка/проверка/обновление/удаление идемпотентны; worker не
      загружает профили.

## 4. Stop-условия (эскалация к оператору)

- Если запрещены даже одноразовые root-операции хоста (загрузка профиля) — вариант 1 в
  текущем виде не реализуем: требуется другой runtime изоляции команд, не компенсация
  Docker-монтированиями.
- Если R4 показывает, что ни одна конфигурация переходов не даёт bwrap работу без
  unconfined — возврат к оператору с протоколом.
