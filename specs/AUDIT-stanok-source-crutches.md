# AUDIT — код-ради-кода, костыли и лишнее в stanok (по сорсам)

Дата: 2026-09-10. Зона: супервизор. Сырьё для красной команды. Без дизайна/решений.

## A. Мёртвый код (не подключено — удалить)

1. `scripts/analyze-evidence.py` — ссылается только сам на себя (docstring); никем не
   вызывается. Мёртвый.
2. `hooks/test-lock-dump.sh` — само-описан «P2-probe… Not part of the live circuit»;
   нет в `settings.stanok.json`, никем не вызывается. Мёртвый.
3. `launcher/stanok.py:345-354` `_pending_malware_flags()` + гейт `:533-541` — ищет
   `evidence/malware-scan/pending-*.flag`. **Такой файл никто не создаёт** (malware-scan.sh
   пишет `flags.log`, `:82`), а сам hook — **PreToolUse**, тогда как docstring (`:346`)
   врёт «PostToolUse». Гейт недостижим → мёртвая ветка + неверный комментарий.
4. `tests/_diag.test.js` (130 б), `tests/_probe.test.js` (124 б) — пустые закоммиченные
   заготовки («contents removed per cleanup»), матчат гейт-глоб.

## B. Дублирование контрактов (дрейф уже случился)

5. Вердикт теста в ТРЁХ раннерах: `verifier.sh:90` (`node file`), `stanok.py:280`
   (`node --test --test-force-exit`), `run.sh:47` (`node file </dev/null`, все файлы).
   Эмпирика: проходящий тест с не-unref интервалом → **rc=124** vs **rc=0** по одному файлу.
6. Ключ лока реализован трижды: `verifier.sh:61-62`, `test-lock.sh:48-49`, `stanok.py:335`.
7. Схема `summary.json` в двух независимых копиях: `write_summary` (`:622-670`) и
   `early_abort` (`:926-944`). Их значения уже не выводятся друг из друга.
8. Список инструментов дважды: `CURATED_TOOLS` (`stanok.py:62`) и `permissions.allow`
   (`settings.stanok.json:25-32`).
9. Имя модели — 5× в settings + default `stanok.py:44` + 2 README (значения уже расходились).
10. Классификатор «что такое src/test» — в 6 файлах (stanok.py, verifier, test-lock,
    malware-scan, read-guard, run.sh).

## C. Костыли / лишние механизмы

11. `src/main.js` — закоммиченный «thin synchronous passthrough on `process.stdout.write`»
    (`docs/fire.md:38`) — обход сломанного теста, который лок (`test-lock.sh:52`) не дал
    исправить. Плакатный костыль CC-059.
12. Двойной dirty-check: `dirty_tree_gate()` (`:146`, rc=22) и `reset_repo()` (`:203`,
    rc=14) гоняют один `git status --porcelain`; внутри песочницы дерево между ними
    измениться не может.
13. PID проброшен тремя механизмами: маркер-файл `START_TS PID` (launch.sh:127,
    stanok.py:706-721), env `STANOK_HOST_PID` (sandbox-run.sh:118), `recorded_pid`.
14. `TURN_TIMEOUT_S <= API_TIMEOUT_S` → авто-подъём (`stanok.py:58-59`) — магическая правка.
15. `_extract_usage` (`:389-401`) и `_safe_json_default` (`:98-103`) — 4-веточная
    защита (dataclass/dict/`__dict__`/str) на объектах, тип которых известен из SDK.

## D. Избыточная поверхность / горячий путь

16. `cmd_watch` (`:843-860`) + `watch` в CLI/README — реализовано и задокументировано, но
    роль супервизора КАТЕГОРИЧЕСКИ запрещает смотреть логи на ходу
    (`CLAUDE.supervisor.md:44-46`) → потребителя нет.
17. `--direct` — проброшен через `launch.sh:75,97` + argparse (`:890`) + README, но
    супервизором не вызывается нигде.
18. Горячий путь на каждый Write/Edit: malware-scan делает ~5-6 форков (`jq`+`python3`),
    verifier — `realpath`/`sha256sum`/`awk`/`jq`/`git`/`node`. Можно резать.
19. `read-guard.sh:53` печатает `systemMessage` на КАЖДЫЙ разрешённый Read — шум на каждом чтении.
20. `doctor.sh` тащит встроенный mock HTTP-сервер (`:121-136`) и 4 `mktemp`-тикета — тяжёлая
    оснастка внутри хука.
21. Телеметрия дублируется: `job["turn_telemetry"]` дублирует `tokens`; события пишутся
    сразу в `events.jsonl` + `session-*.jsonl` + `launcher.stdout.log`.

## E. Твой пример (Docker-упаковка headless-бинарника) — что он снимает

**Это идея оператора, не моя.** Наблюдение по коду: `bwrap`+`hooks` даёт RO-монтирование,
no-network, allow-list команд, детерминированные гейты. Упаковка headless-бинарника в
Docker закрывает тот же периметр иначе (герметичный rootfs, сетевые политики, воспроизводимость)
и убирает `sandbox-run.sh` (PATH-пляски, `--ro-bind`-список, carve-out'ы) вместе с частью
хуков, чья работа — FS-изоляция. Решение о замене — за красной командой.
