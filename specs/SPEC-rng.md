# SPEC-rng — детерминированный сид-PRNG

Модуль `src/rng.js` (чистый Node, без зависимостей):
- `mulberry32(seed)` → `() => float в [0,1)`, детерминированный, без `Math.random`.
- `randInt(rng, min, max)` → целое в [min,max] включительно; min>max → RangeError.
- `pick(rng, arr)` → элемент arr; пустой arr → RangeError.
- `shuffle(rng, arr)` → Fisher-Yates in-place, возвращает тот же ref, перестановка.

Цель: воспроизводимые анимации fire/fire3d (те же искры/угли при том же seed).
Тикет: TASK-STANOK-CC-046.
