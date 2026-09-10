# TASK-STANOK-CC-050 — архитектурные нестыковки, Ticket Shadowing, DoS-защита, очистка хоста

Статус: `[x] DONE` (выполнено супервайзером на хосте — инфраструктурные правки, не код проекта)

## 1. CLAUDE.supervisor.md — DoS-защита (Role-Leak)

§4.3: в список фатальных инфраструктурных кодов добавлен `rc=24` (role leak — `CLAUDE.md`
в родительском репо) наравне с `rc=20/21/22`. `rc=24` эскалируется человеку немедленно,
3 ретрая на нём не сжигаются.

## 2. stanok/launcher/stanok.py — Ticket Shadowing

`_resolve_ticket`: порядок кандидатов приведён к README (project root -> machine root -> as given).
Раньше machine root имел приоритет — одинаковый относительный путь в `stanok/tickets/`
перекрывал корневой `tickets/`.

## 3. stanok/hooks/verifier.sh — stored_hash fail-closed

- Убран слепой `|| true`: сбой чтения lock-файла → явная ошибка в stderr + `return 1`.
- Оба call-sites (Phase B/C) теперь `|| { emit "VERIFY: FAIL (...CORRUPT...)"; exit 1; }`
  (хук работает под `set -uo pipefail` без `-e` — без guard сбой подстановки был бы
  проглочен, и битый lock дал бы тихий PASS).

## 4. stanok/launch.sh — рефакторинг имени

`PROJECT_ROOT` → `STANOK_ROOT` (переменная хранит путь к сабмодулю `stanok/`).

## 5. stanok/sandbox-run.sh — мёртвый bind

Удалена строка `--ro-bind "$REPO_ROOT/.git/config" ...` (весь `.git` уже смонтирован
`--ro-bind` строкой выше).

## 6. P0-launch.sh — надёжность

- `no_proxy` НЕ тронут (`192.168.8.131,localhost,127.0.0.1` — обход прокси для сервера).
- Упрощён server-check: убрана косвенность `MODEL_LINE`/`case`, пустой ответ curl →
  немедленный `exit 1`.
- Fallback при падении парсинга JSON: `read ... || { MODEL_NAME="?"; ... }`.

## 7. stanok/README.md — синхронизация

Structure: `.git` монтируется строго read-only (`--ro-bind`); удалено устаревшее
упоминание tmpfs на `.git/hooks`. Порядок резолвинга тикетов (:31) уже совпадает с кодом.

## Смоки (ЭТАП 3)

- resolve-priority: тикет в parent и в machine root → резолвится в parent (SMOKE-RESOLVE-OK),
  артефакты удалены, `stanok/tickets` убрана.
- stored_hash (sed-экстракция): missing → пусто/rc=0; valid lock → хэш; каталог вместо
  lock → rc=1 + stderr (SMOKE-HASH-MISSING-OK, SMOKE-HASH-READ-OK, SMOKE-HASH-CORRUPT-OK).
- `bash -n` launch.sh / sandbox-run.sh / P0-launch.sh — OK.
- `DOCTOR_EXPECT_NO_CLOUD=1 bash hooks/doctor.sh` → 14 ok, 0 fail.
- `git status --porcelain` — оба дерева чистые.
