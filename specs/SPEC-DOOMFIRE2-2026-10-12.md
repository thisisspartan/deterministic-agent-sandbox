# SPEC-DOOMFIRE2 — терминальный огонь как в Doom (пересборка волны после clean)

Заказ оператора 2026-10-12: «прогриль себя, нарежь тикетов по созданию
реалистичного огня в консоли как в Doom, тикеты передай в станок, меня не
спрашивай». Feature-волна: deliverables в `src/tests/docs`, инфраструктура
не трогается (FROZEN не нарушен — прецедент DOOMFIRE 2026-10-11, spec §0).

## 0. Реальное окружение (гриль-факты, проверено на дереве 2026-10-12)

- `stanok/src/` и `stanok/tests/` ПУСТЫ (clean-коммит `9bfd5e3` удалён код
  закрытой волны DOOMFIRE CC-240..244). Дерево чистое.
- `scripts/run.sh` существует; реестр `scripts/stacks/*.toml` на месте
  (py → pytest `tests/**/*_test.py`). → все тикеты: `run.sh: exists`.
- Сеть в поде закрыта (кроме модельного сервера) → node-pty невозможен;
  PTY-E2E только на Python stdlib `pty` (доказано волной 2026-10-11).
- Алгоритм/рендер/цикл — дословно доказанная спецификация
  `specs/SPEC-DOOMFIRE-2026-10-11.md` (5/5 DONE, все CLEAN-FIRST). Новая
  волна = пересборка по той же контрактной спецификации (KISS: проверенный
  дизайн не переизобретаем).

## 1. Контракт (без изменений, цитируется из SPEC-DOOMFIRE-2026-10-11)

- PSX Doom Fire (Sanglard): bottom-up проход, `dst = x - rand + 1 + wind`,
  `buf[y-1][dst] = max(0, src - (rand & 1))`, rand ∈ [0..3], wind ∈ [-3..3].
- Палитра 37 RGB-кортежей классической Doom-палитры (полный список — в
  тикете CC-248).
- Half-block ▀ truecolor, PAIR_CACHE 37×37 precomputed, alt-buffer
  enter/exit ровно один раз, SIGWINCH-флаг только на tick start,
  non-blocking raw-mode input (стрелки = wind/intensity, q = quit).

## 2. Тикеты (порядок обязателен; каждый — зелёный полный suite)

| Ticket | Deliverables | Суть |
|---|---|---|
| CC-248 (FIRE2-01) | `src/fire_engine.py` + tests | палитра+математика, чистые функции, детерминизм через seed |
| CC-249 (FIRE2-02) | `src/fire_render.py` + tests | half-block рендер + кэш 37×37 + alt-buffer константы |
| CC-250 (FIRE2-03) | `src/fire_main.py` + tests | цикл FPS/resize-flag/teardown (testable seams) |
| CC-251 (FIRE2-04) | `src/fire_input.py`, edit `src/fire_main.py` + tests | raw-mode input → wind/intensity |
| CC-252 (FIRE2-05) | `tests/fire_pty_test.py` | stdlib-pty E2E: ▀+truecolor в байтах, SIGINT→teardown, SIGWINCH→выживание |

Contract-lock: каждый последующий тикет НЕ трогает tests/ предыдущих;
`edit:` разрешён только для src-файлов волны.

## 3. Приёмка (обычная SUCCESS-цепочка, не smoke)

Каждый тикет: launch → summary.json rc=0, verifier PASS, probe_result не
CONTRACT-FAIL → `[x] DONE` в STATUS.md → следующий тикет. Финал волны:
полный suite зелёный + PTY-E2E доказывает TTY-теardown без человека.
