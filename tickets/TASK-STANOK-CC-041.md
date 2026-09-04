# TASK-STANOK-CC-041 — fire3d: объёмный 3D-огонь в консоли с вращением стрелками ←/→

## Контекст (текущее состояние)
В `stanok/` есть работающий 2D-модуль `src/fire/` (fire.js — физика+рендер,
ui.js — attach-цикл, main.js — entry, diag.js) и тесты `tests/fire/`.
Его контракты (для ориентира, НЕ для изменения):
- `src/fire/fire.js`: `create(opts)` → state с `heat` (Float32Array W×H),
  `step()`, `render(state, width) → string`; PRNG `mulberry32(seed)` по
  `opts.rng`; глифы плотности `FLAME_GLYPHS`, тёмный фон `234` (`DARK_BG`).
- `src/fire/ui.js`: `attach(io, fire, opts)` — raw mode, alt screen
  (`\x1b[?1049h`/`l`), cursor hide/show, fixed-timestep 30 FPS loop,
  выход по одиночным `q`/`Q`/`ESC`/`Ctrl+C`, CSI-последовательности
  (стрелки) игнорируются; восстановление терминала ВСЕГДА при stop.
- `src/fire/main.js`: TTY → attach; non-TTY → фиксированное число кадров и
  `process.exit(0)`.

Создать НОВЫЙ модуль `src/fire3d/` — объёмный огонь в 3D, который можно
вращать стрелками ←/→ вокруг вертикальной оси. **`src/fire/` и
`tests/fire/` — НИ ОДНОЙ строки не менять.**

## Задача
Консольная программа `fire3d`: 3D-пламя в объёме W×H×D, ASCII-рендер на
тёмном фоне, вращение сцены стрелками ←/→ (удержание стрелки = плавное
непрерывное вращение за счёт автоповтора терминала). Выход — `q`/`Q`/`ESC`/
`Ctrl+C`.

## Требования

### 1. `src/fire3d/fire3d.js` — физика + рендер (чистая логика)
- `create(opts)`: 3D-сетка `W×H×D` (дефолт 48×24×48, через opts), поле
  `heat` — плоский Float32Array размера W*H*D (индекс `y*W*D + x*D + z`
  или любая фиксированная схема — задокументировать). `opts.rng` —
  инжектируемый PRNG (дефолт `mulberry32(seed)`, `opts.seed` дефолт 1337).
  State содержит также `angle` (радианы, дефолт 0).
- `step(state)`: нагрев снизу вверх по y: нижний слой `y=0` — базовая
  температура ~1.0 с фликером (шум rng); остальные слои:
  `heat[y][x][z] = avg(соседей слоя y-1: (x-1..x+1)×(z-1..z+1)) * decay +
  noise*sparkle`, `decay ≈ 0.85..0.92`, clamp [0..1]. Пламя распространяется
  во всех трёх измерениях (объёмное).
- Детерминизм: один seed + одна последовательность `step()` → идентичные
  кадры `render()`.
- `render(state, width, angle) → string` (чистая функция; `angle` можно
  передавать явно, иначе — `state.angle`): поворот вокселей вокруг
  вертикальной оси (y) на `angle`: `x' = x*cos − z*sin`,
  `z' = x*sin + z*cos` (координаты относительно центра сечения);
  проекция на экран: col из `x'` (масштаб под `width`), row из `y`
  (y=0 — нижний ряд). На каждую экранную ячейку — voxel с максимум heat
  (пустая ячейка → тёмный фон `234`). Глифы плотности по heat
  (набор как `FLAME_GLYPHS` в fire: от редкого к плотному). Кадр одним
  строковым блоком (курсор в начало, строки, очистка хвоста) — как в fire.
- Кирпичей/рамы нет: пламя на всю сетку.

### 2. `src/fire3d/ui.js` — UI-цикл
- `attach(io, fire, opts)` — тот же паттерн, что `src/fire/ui.js`:
  raw mode, alt screen + cursor hide при старте, восстановление (курсор +
  выход из alt) ВСЕГДА при stop, fixed-timestep 30 FPS loop
  (`opts.fpsMs`, catch-up как в fire).
- Парсинг ввода:
  - одиночные байты `q`/`Q`/`ESC`(0x1b)/`Ctrl+C`(0x03) → `stop()` +
    `onQuit(reason)` (как в fire, тикет 038);
  - CSI `\x1b[D` (←) → `fire.angle -= ROT_STEP`;
  - CSI `\x1b[C` (→) → `fire.angle += ROT_STEP`;
  - `ROT_STEP ≈ 5°` (π/36);
  - прочие CSI-последовательности (F-клавиши и т.п.) игнорируются.
  Удержание стрелки даёт автоповтор CSI → плавное непрерывное вращение.
- Рендер каждого кадра: `render(fire, io.columns, fire.angle)`.

### 3. `src/fire3d/main.js` — entry point
- TTY → `attach(process.stdin, fire, { onQuit: () => process.exit(0) })`.
- Non-TTY guard: отрендерить фиксированное число кадров (например 10,
  с `step()` между кадрами) в stdout и `process.exit(0)`. Не вешается.

### 4. `tests/fire3d/` — тесты (TDD, `node:test` + `node:assert/strict`)
- физика: нагрев снизу вверх (после N step heat выше у основания),
  затухание с высотой, 3D-распространение (heat > 0 в разных z при
  одинаковых x,y), детерминизм по seed (два create с одним seed →
  идентичные кадры после N step);
- рендер: `render` — чистая функция, возвращает string; кадр при
  `angle=0` и `angle=π/2` РАЗНЫЙ; пустая сцена (heat всё 0) — только тёмный
  фон, без глифов пламени; в кадре нет кирпичных глифов `▓ █ ▒`;
- ui: mock io (как в `tests/fire/ui.test.js`) — start/stop, выход по
  q/ESC/Ctrl+C, восстановление терминала (cursor show + alt off),
  CSI `\x1b[D` уменьшает `fire.angle`, `\x1b[C` увеличивает, CSI стрелок
  НЕ вызывает выход;
- производительность: 100 итераций `step()+render()` < 2000 мс.

### 5. `docs/fire3d.md`
Запуск (`node src/fire3d/main.js`), управление (←/→ вращение,
q/Q/ESC/Ctrl+C выход), параметры (seed, размеры сетки, fps), как читать
глифы плотности.

## Порядок работы (укладывайся в один ход)
1. `src/fire3d/fire3d.js` одним Write (физика + render).
2. `tests/fire3d/physics.test.js`, `tests/fire3d/render.test.js` — Write.
3. `src/fire3d/ui.js` одним Write.
4. `tests/fire3d/ui.test.js`, `tests/fire3d/perf.test.js` — Write.
5. `src/fire3d/main.js`, `docs/fire3d.md` — Write.
6. ОДИН запуск: `node --test tests/fire3d/ && node --test tests/fire/` —
   если зелёные, готово. Не перечитывай написанные файлы, не запускай
   тесты по одному файлу многократно.

## Критерии приёмки
1. `node --test tests/fire3d/` — все тесты зелёные.
2. `node src/fire3d/main.js` в non-TTY: печатает кадры, exit 0, < 10 c.
3. `node --test tests/fire/` — все существующие тесты fire зелёные
   БЕЗ ИЗМЕНЕНИЙ (модуль fire не тронут).
4. 100 кадров (step+render) < 2 c.
5. `docs/fire3d.md` создан. Никаких внешних зависимостей.
