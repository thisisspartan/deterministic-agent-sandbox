# TASK-STANOK-CC-023 — tetris: main (сборка, запуск, SIGINT cleanup, smoke e2e)

## Контекст

Консольный тетрис, модуль 6 из 6 (финальный). Зависимости: `src/tetris/game.js` (021),
`src/tetris/ui.js` (022). Специка: `specs/SPEC-tetris.md` («Критерии приёмки (общие)»,
п.11–12, «API-контракты → 023»). Не трогать существующие модули станка и
game/ui/pieces/board/bag.

## Требования

1. Файл `src/tetris/main.js` (CommonJS, точка входа: `node src/tetris/main.js`).
2. Сборка: `newGame({ seed: Date.now(), now: () => Date.now() })` +
   `ui.attach({ stdin: process.stdin, stdout: process.stdout, columns: process.stdout.columns }, game, { now: () => Date.now() })`.
3. **Q** → `stop()` + exit(0). **R** (из game-over) → `game.reset(Date.now())`.
4. **SIGINT/SIGTERM:** обработчики → `stop()` (raw-mode off, курсор показать) + exit.
   Тест: после SIGINT tty восстановлен (raw-mode off).
5. Game-over экран: score/lines/level + «R — заново, Q — выход» (рендерится ui.render).
6. Smoke e2e: игра запускается, не падает на старте, отвечает на ввод (Q выходит).
7. `package.json`: убедиться что `dependencies` пуст/отсутствует (нет внешних зависимостей).
   Если станок использует `npm start` — добавить script `"start": "node src/tetris/main.js"`
   (только если package.json уже есть и не ломается).

## Тесты (`tests/tetris/main.test.js`, `node --test`)

- Smoke: запустить main в child (или импортировать и вызвать init с mock-io) →
  не бросает исключение на старте, render произошёл.
- SIGINT: отправить SIGINT child-процессу → процесс завершился, exit code 0/130,
  tty не в raw-mode (проверить `process.stdin.isRaw` до/после в child, либо mock).
- Q: mock stdin пишет 'q' → stop вызван, exit.
- R из game-over: mock game.over=true, stdin 'r' → game.reset вызван.

## Критерии приёмки (ФИНАЛЬНЫЕ, по спеке)

- `node --test tests/tetris/` — ВСЕ тесты всех 6 модулей зелёные (018–023).
- `node src/tetris/main.js` — игра запускается, управляется, game over → R/Q работают.
- Нет внешних зависимостей (`package.json` без `dependencies` или `dependencies: {}`).
- Git diff — только `src/tetris/`, `tests/tetris/`, `docs/tetris.md` (+ package.json script).
- Существующие модули станка (`src/*.js` корня, `tests/*` корня) НЕ изменены.
- `docs/tetris.md` — полная дока: запуск, управление, модули, правила.
