# TASK-WWWJS-06: Мёртвые поля + чистка LCP-условия + полл при живом SSE

Supervisor-executed (www.js на 192.168.8.131, не машина).

## Проблема

1. `ramCache.cpEstAt` (:44) — write-only (пишется :291/:315/:343, нигде не
   читается) → мёртвое поле.
2. `state.task.fromHostRam` (:119) — write-only (нигде не читается) →
   мёртвое поле.
3. LCP-условие (:200): `line.includes('sim_best')` — субстринг, матчит и
   `f_sim_best`. По реальному логу существует только `f_sim_best =`
   (13335 строк; голого `sim_best =` — 0), поэтому живого дефекта нет, но
   условие небрежное.
4. Фронтенд: `pollFallback` гоняется каждые 400мс параллельно с живым SSE
   (двойной рендер); `if (updateBusy) return` (:1269/:1278) роняет
   SSE-сообщения во время полла (транзиентно, ≤400мс, но лишний трафик).

## Изменения (~/www.js)

1. Удалить `cpEstAt` из `state.ramCache` (:44) и все три записи (:291, :315,
   :343).
2. Удалить `state.task.fromHostRam = isFromHostRam;` (:119) — вместе с
   полем в `freshTaskState()` (WWWJS-04).
3. LCP-условие (:200): `line.includes('sim_best')` →
   `line.includes('f_sim_best =')`.
4. Фронтенд: `pollFallback` — `if (updateBusy || sseWorking) return;`
   (полл — только фолбэк; `es.onerror` уже ставит `sseWorking = false`,
   полл возобновится сам).

## Acceptance

- `grep cpEstAt` / `grep fromHostRam` по файлу → 0 совпадений.
- Локальный тест: LCP-ветка на реальных строках (`checking sim =`,
  `f_sim_best =`) — поведение без изменений (pendingLcp = f_sim_best).
- Регрессия: ngram 10/10, ram-est 20/20, тесты WWWJS-04/05 зелёные.
- Live: HTTP 200, /api/state без cpEstAt; панель обновляется (SSE жив).
