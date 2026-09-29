# TASK-FIRE-08: Seeded deterministic PRNG in the fire simulator

edit: src/fire/simulator.py
test: tests/fire_determinism_test.py
run.sh: exists

## Задача

Сделать симулятор огня детерминированным по seed, чтобы последующие
фичи реализма можно было проверять headless-тестами на идентичность
кадров. Сейчас `src/fire/simulator.py` использует модульные функции
`random.*` (глобальное состояние), поэтому два одинаковых запуска дают
разные кадры.

### Изменения в `src/fire/simulator.py`

1. В `FireSimulation.__init__` добавить параметр
   `seed: Optional[int] = None` (в конец сигнатуры, после `decay_max`) и
   создать `self._rng = random.Random(seed)`. `seed=None` → энтропия
   системы (текущее недетерминированное поведение), `seed=42` →
   детерминированная последовательность.
2. Заменить ВСЕ обращения к модульному `random.*` на `self._rng.*`
   (те же методы, тот же порядок вызовов):
   - `update_wind`: `random.uniform(0.05, 0.2)` → `self._rng.uniform(...)`
   - `spawn_sparks`: `random.choice(candidate_rows)`,
     `random.randrange(self.width)`,
     `random.randint(_EMBER_MIN_HEAT, _EMBER_MAX_HEAT)` → `self._rng.*`
   - `ignite_bottom`: `random.random()`,
     `random.randint(intensity_min, intensity_max)` → `self._rng.*`
   - `step`: `random.choice((-1, 0, 1))`,
     `random.randint(self.decay_min, self.decay_max)` → `self._rng.*`
3. Логика (порядок вычислений, клампинг, подъём углей, ветвление по
   ветру) НЕ меняется — только источник случайности.

## Тесты (TDD: сначала тесты, они должны падать до фикса)

Новый `tests/fire_determinism_test.py` (существующие тесты не менять и не
удалять — верификатор прогоняет все):

- `test_same_seed_same_buffer`: два `FireSimulation(width=20, height=10,
  seed=42)`; для каждого: `ignite_bottom()`, затем 30 раз
  `update_wind(); step(); spawn_sparks()`; буферы идентичны
  (`[row[:] for row in a.buffer] == [row[:] for row in b.buffer]`).
- `test_different_seed_differs`: то же самое, но `seed=42` и `seed=43` →
  буферы НЕ идентичны.
- `test_seed_none_still_valid`: `FireSimulation(width=10, height=8)`
  (seed по умолчанию), `ignite_bottom()` + 5×`step()` → все значения в
  `[0..255]` (обратная совместимость: seed=None не ломает поведение).

## Ограничения

- Чистый stdlib, без новых зависимостей.
- Не менять сигнатуры `update_wind`, `spawn_sparks`, `ignite_bottom`,
  `step` (только добавить `seed` в `__init__`).
- Не трогать `src/fire/palette.py`, `src/fire/renderer.py`,
  `src/fire/cli.py`, `scripts/run.sh`.
- Существующие тесты `tests/simulator_test.py` должны остаться green
  (они property-based; их `random.seed(N)` становится no-op, но все
  ассерты по-прежнему выполняются).

## Gate / Проверка

- `bash scripts/run.sh test tests/fire_determinism_test.py` — green.
- `bash scripts/run.sh test tests/simulator_test.py` — green (регрессия).
- `bash scripts/run.sh test --all` — green.
