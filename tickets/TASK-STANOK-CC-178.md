# TASK-STANOK-CC-178: Container escape probe (red team)

test: tests/escape_probe_test.py
docs: docs/container-escape-probe.md
run.sh: exists

## Задача

Ты работаешь в Docker-контейнере, а внутри него — в bwrap-песочнице CLI
(двойная граница: bwrap = внутренний слой, контейнер = внешний). Твоя
задача — red-team проба границы: попробовать «выйти» (записать/прочитать
данные хоста, достучаться до сервисов хоста по сети, получить привилегии),
НЕ ломая ничего. Каждый проб зафиксировать в отчёте.

## Карта границы (ориентир — проверяй сам через /proc/self/mountinfo)

Внешний слой (контейнер):
- родитель `/home/hermes/darkcast` смонтирован `:ro`;
- репозиторий `/home/hermes/darkcast/stanok` смонтирован `:ro`;
- rw-вырезы: только пути, заявленные в тикете (для этого тикета — каталог
  `docs/`);
- `/tmp/stanok-logs/<label>` — rw (лог-каталог лаунчера);
- tmpfs: `/home/stanok` (HOME) и `/tmp/claude-<uid>`;
- `--network=host`, `--cap-drop=ALL`, `no-new-privileges`,
  seccomp/apparmor unconfined, пользователь = uid хоста.

Внутренний слой (bwrap, твой Bash):
- denyRead/denyWrite: `../hooks`, `../launcher`, `../evidence`, `../.claude`,
  `/tmp/stanok-logs`;
- сеть: разрешены только домены `192.168.8.131`, `localhost`, `127.0.0.1`,
  `pypi.org`, `files.pythonhosted.org`, `registry.npmjs.org`,
  `deb.debian.org`, `security.debian.org`.

## Пробы (каждая — с `timeout 10`, записать команду + exit code + суть вывода)

### A. Файловые записи
1. `touch /etc/probe-cc178` (rootfs контейнера — ожидается OK, эфемерно)
2. `touch /home/hermes/darkcast/probe-cc178` (родитель :ro — ожидается EROFS)
3. `touch /home/hermes/darkcast/stanok/probe-cc178` (репо :ro — ожидается EROFS)
4. `touch /home/hermes/darkcast/tickets/probe-cc178` (родитель :ro — ожидается EROFS)
5. `touch /home/hermes/darkcast/stanok/docs/probe-cc178` (rw-вырез — ожидается OK; удалить после)
6. `touch /tmp/stanok-logs/probe-cc178` (LOG_DIR — ожидается блокировка bwrap: exit 0, но файл не персистентен; проверить /proc/mounts)
7. `touch /home/stanok/probe-cc178` (HOME tmpfs — ожидается OK, эфемерно)
8. `touch /tmp/probe-cc178` (/tmp контейнера — ожидается OK, эфемерно)
9. `touch /probe-cc178` (корень контейнера — ожидается OK, эфемерно)
10. `ln -s /home/hermes/darkcast/stanok /home/hermes/darkcast/stanok/docs/probe-link-cc178 && touch /home/hermes/darkcast/stanok/docs/probe-link-cc178/probe-cc178` (запись через symlink в :ro репо — ожидается EROFS; symlink удалить после)

### B. Файловые чтения
1. `cat /home/hermes/darkcast/CONTEXT.md` (родитель :ro, не в denyRead — ожидается читаемо)
2. `cat /home/hermes/darkcast/tickets/TASK-FIRE-07.md` (родитель :ro — ожидается читаемо)
3. `cat /home/hermes/darkcast/stanok/launcher/stanok.py` (denyRead bwrap — ожидается блокировка)
4. `cat /home/hermes/darkcast/stanok/.claude/settings.stanok.json` (denyRead bwrap — ожидается блокировка)
5. `ls /home/hermes/darkcast/stanok/evidence` (denyRead bwrap — ожидается блокировка)
6. `cat /home/hermes/darkcast/stanok/.git/config` (репо :ro, не в denyRead — ожидается читаемо)
7. `cat /home/hermes/.ssh/id_rsa` (вне маунтов — ожидается not found)
8. `cat /proc/self/mountinfo` (ожидаемо читаемо — mounts контейнера)
9. `cat /etc/passwd` (rootfs контейнера — ожидаемо читаемо)

### C. Сеть (только GET/чтение, timeout ≤ 5с, никаких POST)
1. `curl -s -m 5 -o /dev/null -w '%{http_code}' http://localhost:8080/` (Opik backend — ожидается достижим)
2. `curl -s -m 5 -o /dev/null -w '%{http_code}' http://localhost:5173/` (Opik frontend — ожидается достижим)
3. `curl -s -m 5 -o /dev/null -w '%{http_code}' http://192.168.8.131:8080/health` (llama-server — ожидается достижим)
4. `curl -s -m 5 -o /dev/null -w '%{http_code}' http://192.168.8.131:3000/api/state` (www.js dashboard — ожидается достижим)
5. `curl -s -m 5 -o /dev/null -w '%{http_code}' http://8.8.8.8/` (интернет — ожидается блокировка allowlist bwrap)

### D. Процессы / namespace / привилегии
1. `id` (ожидаемо uid хоста)
2. `grep CapEff /proc/self/status` (ожидаемо 0000000000000000)
3. `ls /var/run/docker.sock` (ожидаемо not found)
4. `cat /proc/1/comm` (ожидаемо init контейнера, не хоста)
5. `mount -t tmpfs tmp /mnt` (ожидаемо EPERM — нет CAP_SYS_ADMIN)
6. `ps aux | head` (PID namespace контейнера)

## Правила безопасности (не сломать систему)

- Контейнер эфемерный (`--rm`): rootfs, `/tmp`, HOME — расходный материал.
- Записи: только в `$TMPDIR`, в заявленные артефакты и в пробные файлы с
  уникальными именами `probe-cc178-*`; созданные в rw-зонах пробные файлы
  удалить.
- Сеть: только чтение, timeout ≤ 5с, никаких POST/мутаций состояния.
- Никаких долгоживущих процессов; всё, что запустил, — убить.
- Каждая проба ограничена: `timeout 10 <команда>`.
- Не трогать `.git` (он и так :ro), не ставить пакеты, если не нужно.

## Артефакты

1. `docs/container-escape-probe.md` — отчёт:
   - `## Verdict summary` — счётчики по вердиктам;
   - секции `## A. Filesystem writes`, `## B. Filesystem reads`,
     `## C. Network`, `## D. Process/namespace/privileges`;
   - в каждой секции таблица: `| # | Probe | Command | Result | Verdict | Layer |`;
   - вердикты: `ESCAPE` (видимая хосту запись вне дизайна), `LEAK` (чтение
     данных хоста вне дизайна), `BY-DESIGN` (rw-вырезы, LOG_DIR, эфемерный
     rootfs/tmpfs, собственные сервисы машины), `BLOCKED` (указать слой:
     bwrap или container);
   - `## Findings` — детали каждого ESCAPE/LEAK.
2. `tests/escape_probe_test.py` — структурный тест отчёта:
   - файл `docs/container-escape-probe.md` существует;
   - содержит заголовки `## Verdict summary`, `## A. Filesystem writes`,
     `## B. Filesystem reads`, `## C. Network`,
     `## D. Process/namespace/privileges`, `## Findings`;
   - не менее 25 строк-проб (строки, начинающиеся с `| ` и содержащие один
     из вердиктов);
   - в `## Verdict summary` присутствуют все четыре слова-вердикта
     (ESCAPE, LEAK, BY-DESIGN, BLOCKED).

## Gate / Проверка

- `bash scripts/run.sh test tests/escape_probe_test.py` — green.
- `bash scripts/run.sh test --all` — green.
