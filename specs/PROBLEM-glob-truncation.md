# PROBLEM — Glob `**/*` обрезка: `.git/objects` скрывает `src/` и `evidence/`

Статус: **B1 реализован (коммит `7ce709f`: правило в CLAUDE.md станка, шаг 2) и подтверждён прогоном main-005-xl-fixAp: обрезки нет, «дерева стёрто» нет, `AskUserQuestion` нет; модель исследовала репо точечными Glob с явным `path`. Остаток: 2 стартовых Glob с префиксом `stanok/` → «No files found» (самоисправление за 2 шага).**
Дата фиксации: 2026-08-25. Источник: транскрипт `23fe6f19` (прогон `main-005-xl-fixA`),
строки 28–29 (вызов) и 50 (повтор, 100 of 267).

## Проблема

`Glob **/*` по корню репо возвращает урезанный список:

```
(Showing 100 of 265 matching files; 165 more are not listed.
 Narrow the pattern or path to see the rest.)
```

Видимые 100 (транскрипт, строка 29): `.claude/agents/*`, `hooks/*`, `live.py`,
`.gitignore`, `src/.gitkeep`, `tickets/.gitkeep`, `tests/.gitkeep`, `docs/.gitkeep`,
`.git/description`, `.git/info/exclude`, `.git/hooks/*.sample`, `.git/objects/*`
(loose objects). **Не видны:** `src/*.js`, `evidence/`, `specs/*.md`,
`tickets/*.md`, `CLAUDE.md`, `launch.sh`. Хвост списка съедают `.git/objects/*`.

Почему ignore-файлы не лечат: Glob в этой сборке `.gitignore` не уважает
(подтверждено в `PROBLEM-launch-log-selfref.md`: `evidence/` в `.gitignore`,
но Glob его показал). Значит, `.git/` тоже не исключается.

## Последствия в прогоне `23fe6f19`

1. Модель видела `src/.gitkeep`, но не `src/*.js` → сделала вывод «дерево стёрто»
   → `AskUserQuestion` оператору (TG, 28.8s; ответ «Allow» ≠ ответ на вопрос,
   инструмент вернул «user did not answer»; модель продолжила и завершилась чисто).
2. До этого — 7× «No files found»: модель использовала L1-пути с префиксом
   `stanok/` (`stanok/src/*.js`, `stanok/**/*`, ...) без параметра `path`, хотя
   cwd сессии — корень репо (`/home/hermes/darkcast/stanok`). Относительные
   паттерны резолвятся от `path`/cwd, а не от «корня проекта». Повторно:
   `tickets/TASK-STANOK-CC-005.md` с `path=/home/hermes/darkcast` →
   «No files found» (тикeт лежит в `stanok/tickets/`).
3. **Взаимодействие с fix A:** `evidence/` было не видно → self-ref loop (M1)
   не мог сработать → верификация фикса A ослаблена
   (см. `PROBLEM-launch-log-selfref.md`, «Первый прогон верификации», оговорка 2).

Контраст с базой: в `0e15358f` модель передавала `path` явно
(`Glob stanok/evidence/**/*` с `path=/home/hermes/darkcast`) и получала полный
список `evidence/` — включая `launch.log`, что и запустило loop.

## Кандидаты решений (выбран B1)

- **B1.** Инструкция в CLAUDE.md станка: не использовать `**/*` по корню —
  только точечные паттерны (`src/**`, `tests/**`, `evidence/<label>/*`) и
  всегда с явным `path`. Дёшево, но полагается на дисциплину модели.
- **B2.** `git gc`/repack перед прогоном — не лечит: loose objects появляются
  снова, `.git/hooks/*.sample` и прочее остаются; 100 слотов всё равно уходят
  в `.git/`.
- **B3.** A+ (вынести `evidence/` из репо) — уменьшает 265 на число
  evidence-файлов, но `.git/objects` остаётся доминирующим потребником слотов.
- **B4.** Проверить, есть ли в сборке knob лимита/исключений для Glob
  (`.claudeignore` в 2.1.88 отсутствует — см. selfref-спеку).

## Верификация

После фикса — прогон, где модель листает репо. Критерий: `src/*.js` и
`evidence/<label>/` видны в результате Glob; нет «No files found» на
корректных путях; нет «дерево стёрто»-эпизодов и `AskUserQuestion` по этой
причине.
