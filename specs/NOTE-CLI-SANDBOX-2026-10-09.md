# NOTE: внутренний слой песочницы cli.js 2.1.88 — находки из сорсов бандла (вход в X1a)

Дата: 2026-10-09. Источник: `~/git/claude-code-2.1.88` (branch `base`, HEAD c306331) —
`cli.js` (offsets указаны) + image `stanok-machine:latest` (docker-probes). Ничего не менялось.
Контекст барьеров: `NOTE-SANDBOX-BARRIER-2026-10-08.md`; аудит полномочий mount: CONTEXT 2026-10-09.

## 0. Текущая prod-конфигурация (stanok/.claude/settings.stanok.json)
`sandbox.enabled=true`, `failIfUnavailable=true`, `enableWeakerNestedSandbox=true`,
`allowUnsandboxedCommands=false`; denyWrite/denyRead: `../evidence ../hooks ../launcher
../.claude /tmp/stanok-logs`; network.allowedDomains: модель (192.168.8.131), localhost,
127.0.0.1, pypi/pythonhosted/npmjs/debian×2.

## 1. Билдер bwrap-argv (то, что реально исполняется)
`Y54` (cli.js ~4346569) — Linux-билдер; `KC_` (~4343716) — FS-аргументы.
- Безусловно: `--new-session --die-with-parent`, `--dev /dev`, `--unshare-pid`.
- `--proc /proc` — только при `!enableWeakerNestedSandbox` (`!j && Z.push("--proc","/proc")`).
  Prod: weaker=true → `--proc` НЕТ. Единственный mount, который наша модель полномочий
  запрещает (свой /proc = новый bind), уже исключён конфигурацией.
- `KC_`: есть writeConfig → `--ro-bind / /` + `--bind` на каждый allowOnly + защиты
  (`--ro-bind /dev/null` поверх симлинков deny-зон, tmpfs/пустые каталоги против создания
  путей); нет writeConfig → `--bind / /`. denyRead → `--tmpfs` + ре-allow `--ro-bind`.
- Сеть: `--unshare-net` + `--bind` bridge-сокетов + `--setenv` proxy-портов.

## 2. Нативный self-seccomp (новая находка)
- `Y54`: если `!allowAllUnixSockets` → ищет `unix-block.bpf` + `apply-seccomp`
  (`vendor/seccomp/{x64,arm64}/` относительно cli.js ×3 пути + глобальные npm-пути,
  `aK4`/`oK4` ~4335499). Настройки: `sandbox.seccomp.bpfPath` / `sandbox.seccomp.applyPath`
  (zod-схема `hC_`, ~4374320) — произвольные пути. Применение: обёртка команды
  `apply-seccomp <bpf> bash -c cmd` (`Ln6`, `qC_`).
- Если бинарников нет — warn «Seccomp binaries not available - unix socket blocking
  disabled» и работа БЕЗ seccomp (graceful degradation).
- **Эмпирика: в образе их нет** — `find /` по `vendor/seccomp`, `apply-seccomp`,
  `unix-block.bpf` пуст. Значит prod-вложенный bwrap сейчас БЕЗ seccomp-слоя вовсе.
  (Поправка к таблице NOTE-SANDBOX-BARRIER: строка «seccomp unix-socket block ✅
  маргинально» → фактически ❌.)
- UI-подсказка cli.js (~10878433): «npm install -g @anthropic-ai/sandbox-runtime — or copy
  vendor/seccomp/* … and set sandbox.seccomp.bpfPath and applyPath in settings.json» —
  штатный путь подмены фильтра.
- Проверка доступности `_54` (~4341220): bwrap+socat — hard errors; seccomp — только warn.
  Образ: bwrap 0.8.0 ✅, socat /usr/bin/socat ✅.
- Все логи `[Sandbox Linux]`/`[SeccompFilter]` гейлятся env `SRT_DEBUG` (`O7`, ~4316991) —
  в prod-логах невидимы.

## 3. Сетевой механизм (как работает allowlist)
Host: socat `UNIX-LISTEN $TMPDIR/claude-{http,socks}-*.sock → TCP localhost:3128/1080`
(in-process прокси с allowedDomains). Sandbox (`qC_`): socat `TCP-LISTEN:3128/1080 →
UNIX-CONNECT` к bound-сокету + proxy-env. С `--unshare-net` у песочничной команды нет
пути наружу, кроме bridge-сокета → allowlist фактически держится на netns, обход через
`--noproxy` невозможен (нет маршрута).

## 4. Конфиг-рычаги (без патчей)
- `sandbox.enabled:false` — полное отключение обёртки (`Y54: if(!_&&!f&&!G) return K`);
  undocumented `sandbox.enabledPlatforms` — по платформам.
- `allowAllUnixSockets:true` — пропустить seccomp-попытку; `allowUnsandboxedCommands`
  (default true) — per-command лазейка (у нас false).
- Linux-glob-ограничения: glob в write-путях скипаются с warn; glob в denyRead раскрываются.
- `mandatoryDenySearchDepth` (default 3), `allowGitConfig` (default false), `binShell`.

## 5. Сопоставление с вариантами X1a
- **Вариант 1 (bwrap + managed-профили):** нативная альтернатива самописным AppArmor-профилям —
  запечь в образ `apply-seccomp` + свой BPF и указать `sandbox.seccomp.bpfPath/applyPath`.
  Без загрузки в ядро, без профильной пары, без `--security-opt`. Оговорки: штатный
  unix-block.bpf блокирует только AF_UNIX; наш BPF (deny mount/umount/pivot_root для
  песочничных команд) — собственный артефакт (компиляция на хосте); по аудиту capabilities
  уже запрещают mount недоверенным командам — это defense-in-depth, та же роль, что у
  AppArmor. apply-seccomp в образе нет → нужен вендоринг бинарника (сеть контейнера закрыта).
- **Вариант 2 (без вложенного bwrap):** чистый конфиг `sandbox.enabled:false`
  (= вариант B NOTE-SANDBOX-BARRIER) — без патчей.
- `--dev /dev` безусловен: единственный оставшийся mount-рычаг, требующий патча (1 хунк в
  patches/). `--proc` уже исключён prod-конфигом.
- X4-gap подтверждён со стороны cli.js: `_54` проверяет только наличие бинарников на старте;
  per-call отказ bwrap не ловится ничем (тикет #30 остаётся).

## 6. Чего нет (исчерпано)
- Нет нативного «уже в песочнице — не оборачивать» (перепроверено).
- Нет рычага отключить `--dev`/`--unshare-pid`/`--new-session`.
- В bандл-репозитории `vendor/` = audio-capture + ripgrep; seccomp-бинарников нет и там.
