# PLAN: live thinking в строке Tip спиннера (patch cli.js)

Статус: **PASS 2026-09-17 (итерация 12: +M — фикс дублирующего тапа `__lt`: lockstep-дубль в `∴`-сниппете; единственный append — main path).** `node --check` OK, headless smoke OK,
интерактивный тест P1+P2 пройден (сессия PID 2697524; `∴` live-сниппет виден,
tool-стриминг не сломан). P3 (tips off) применён + `spinnerTipsEnabled: false` в
`~/.claude/settings.json`. A (хвост буфера вместо последней строки) применён —
вступит в силу после рестарта/резюма сессии. Статус-лайн `statusline-thinking.sh`
отключён из settings (redundant: не live, дублирует спиннер) — тоже после рестарта.
Откаты: K → `cp cli.js.bak-preK-20260916 cli.js`; J → `cp cli.js.bak-preJ-20260916 cli.js`; I → `cp cli.js.bak-preI-20260916 cli.js`; H → `cp cli.js.bak-preH-20260916 cli.js`; G → `cp cli.js.bak-preG-20260915 cli.js`; F → `cp cli.js.bak-preF-20260915 cli.js`; E → `cp cli.js.bak-preE-20260915 cli.js`; A → `cp cli.js.bak-preA-20260915 cli.js`;
P3 → `cp cli.js.bak-preP3-20260915 cli.js` (+ убрать `spinnerTipsEnabled` из settings);
всё → `cp cli.js.bak-20260915 cli.js`.

## Цель
В TUI (supervisor-сессия) вместо статической `⎿ Tip: ...` во время стриминга показывать
live-сниппет thinking модели (последняя строка текущего thinking-блока, обновляется на
каждом ре-рендере спиннера). Машина (headless stanok) не затрагивается: у неё
`MAX_THINKING_TOKENS=0` → буфер пуст → оригинальная tip-логика.

## Факты (почему так)
- `thinking_delta` SSE-события уже приходят в CLI в реальном времени; сейчас текст
  выбрасывается, используется только для счётчика токенов
  (`source/src/utils/messages.ts:3075` → `onUpdateLength`).
- Statusline НЕ live: перезапускается только при смене `lastAssistantMessageId`
  (`StatusLine.tsx:237-246`) → статус-строка не подходит для live.
- Transcript JSONL пишется по завершении сообщения → tail не даёт live.
- OTEL `thinking_output` — только `USER_TYPE === 'ant'` и в конце span → не подходит.
- Строка Tip — чистый UI-рендер: не попадает в `messages`, не пишется в transcript,
  не отправляется на сервер → **ноль влияния на контекст модели**.
- CLI = один бинарь: `/home/hermes/git/claude-code-2.1.88/cli.js` (минифицированный
  бандл, ~13 МБ, ~8000 строк). `which claude` → сюда же (симлинк из ~/.npm-global).
  Build-скриптов нет; `source/` — только референс. Патчим бандл напрямую.

## Архитектура патча
- Буфер в `globalThis.__lt` (строка, кап 800 символов) + метка времени `globalThis.__ltt`.
- Заполняется ТОЛЬКО в `thinking_delta` (единственная точка тапа).
- Рендер: в точке, где строится строка Tip, если буфер свежий (`< 15 c` с последней
  дельты) → `∴ <последняя непустая строка буфера, ≤120 символов>`, иначе —
  оригинальная логика побайтово. Фрешность по таймстампу → не нужен отдельный сброс
  буфера (после окончания thinking строка сама возвращается к Tip).
- Ветка `Next: <task>` (pending task) сохраняет приоритет — не трогаем.

## Точные патчи (2 точки, оба old-строки уникальны, count=1)

### P1 — тап: line 4824
OLD (точно, 1 вхождение):
```
case"thinking_delta":_(q.event.delta.thinking);return;
```
NEW:
```
case"thinking_delta":_(q.event.delta.thinking);try{globalThis.__lt=(globalThis.__lt||"")+q.event.delta.thinking;if(globalThis.__lt.length>800)globalThis.__lt=globalThis.__lt.slice(-800);globalThis.__ltt=Date.now()}catch(e){};return;
```

### P2 — рендер: line 2203
OLD (точно, 1 вхождение; обратные кавычки — литеральные):
```
p?`Next: ${p.subject}`:`Tip: ${J6}`
```
NEW:
```
p?`Next: ${p.subject}`:(()=>{try{const t=globalThis.__lt;if(typeof t==="string"&&t.length>0&&Date.now()-(globalThis.__ltt||0)<15000){const ls=t.split("\n").map(s=>s.trim()).filter(Boolean);if(ls.length)return"∴ "+ls[ls.length-1].slice(0,120)}}catch(e){}return`Tip: ${J6}`})()
```

Примечание: `J6` — оригинальная tip-переменная (btw/clear/spinnerTip), не меняется.
`∴` — UTF-8, в бандле уже есть юникод.

## P3 — tips off, `∴` независимо от tips (итерация 2, 2026-09-15)

Решение: rotating tips (`/btw`, `/clear`, discovery) для локального сетапа — шум
(решение пользователя). `spinnerTipsEnabled: false` в `~/.claude/settings.json`
глушит tips (tipScheduler.ts:36-38, Spinner.tsx:256-259), но тогда `J6=null` и
оригинальные гейты `p||J6||X6` / `(p||J6)` перестают рендерить и `∴`. Поэтому:

- settings.json: добавлено `"spinnerTipsEnabled": false`.
- P3a — флаг свежести (якорь `X6=null;return Pq.createElement(u,{flexDirection:"column",width:"100%",alignItems:"flex-start"},Pq.createElement(r1K,`):
  вставить перед `return`:
  `const __ltf=(()=>{try{return typeof globalThis.__lt==="string"&&globalThis.__lt.length>0&&Date.now()-(globalThis.__ltt||0)<15000}catch(e){return false}})();`
- P3b — внешний гейт: `p||J6||X6?` → `p||J6||X6||__ltf?`
- P3c — внутренний гейт: `(p||J6)&&` → `(p||J6||__ltf)&&`
- P3d — fallback P2: `return`Tip: ${J6}`` → `return J6?`Tip: ${J6}`:null`
  (tips off → `J6=null` → после 15 c без thinking строка исчезает, а не показывает `Tip: undefined`).

Поведение после P3: thinking → `∴ <сниппет>`; >15 c без thinking → строки нет;
`Next: <pending task>` и override-сообщения (`X6`) работают как раньше.
Бэкап перед P3: `cli.js.bak-preP3-20260915`. Все 4 якоря были уникальны (count=1).

## A — хвост буфера вместо последней строки (итерация 3, 2026-09-15)

Проблема: «последняя непустая строка» буфера при дельтах-фрагментах часто — обрывок
посреди фразы (наблюдено: `∴ This`). Строки thinking — не семантические единицы.
Решение: показывать **хвост потока** — последние 120 символов всего буфера,
переносы → пробелы.

- Бэкап: `cli.js.bak-preA-20260915`.
- OLD (1 вхождение): `const ls=t.split("\n").map(s=>s.trim()).filter(Boolean);if(ls.length)return"∴ "+ls[ls.length-1].slice(0,120)`
- NEW: `const s=t.replace(/\s+/g," ").trim();if(s.length)return"∴ "+s.slice(-120)`
- `const s` в блоке try IIFE — блок-скауп, коллизий с minified-переменными нет.
- Проверено: `node --check` OK, headless smoke `ok`.

## E — отключить effort-уведомление `◐ medium · /effort` (итерация 4, 2026-09-15)

Уведомление `effort-level` (`PromptInput.tsx:1970-1982`, текст из
`EffortIndicator.ts:getEffortNotificationText`) — шум для локального сетапа
(effort всегда medium). Сеттинга для скрытия нет.
- Бэкап: `cli.js.bak-preE-20260915`.
- OLD (1 вхождение): `function PvK(q,K){if(!fL(K))return;let _=GT8(K,q);return`${P78(_)} ${_} · /effort`}`
- NEW: `function PvK(q,K){return}`
- `PvK` в бандле: 2 вхождения (определение + 1 вызов в PromptInput) — безопасно.
- API не затрагивается: effort-параметр по-прежнему отправляется; убран только UI-текст.
- Проверено: `node --check` OK, headless smoke `ok`.

## F — сброс буфера на message_start + обрезка неполного первого слова (итерация 5, 2026-09-15)

Проблема (наблюдено в сессии): снапет в новом вопросе показывал хвост thinking'а
*предыдущего* вопроса + первые слова нового (буфер append-only на всю сессию,
никогда не сбрасывался), плюс хвост-120 резал слово пополам (`∴ me present it as…`).
- Бэкап: `cli.js.bak-preF-20260915`.
- F1 — OLD (1 вхождение, топ-уровневый SSE-хендлер, offset ~11553288):
  `case"message_start":{N6=Y1.message,f6=Date.now()-$6`
  NEW: `case"message_start":{try{globalThis.__lt="";globalThis.__ltt=0}catch(e){};N6=Y1.message,f6=Date.now()-$6`
  Новый ассистентский месседж → пустой буфер → снапет только текущего хода.
- F2 — OLD (1 вхождение): `if(s.length)return"∴ "+s.slice(-120)`
  NEW: `if(s.length){let e=s.slice(-120);if(s.length>120){let sp=e.indexOf(" ");if(sp>=0)e=e.slice(sp+1)}return"∴ "+e}`
  Неполное первое слово отбрасывается только если буфер длиннее 120 (короткий
  thinking показывается целиком).
- Проверено: `node --check` OK, headless smoke `OK`. Коммит `a3d359c` на `base`.

## G — строка `∴` только при буфере ≥ 24 символов (итерация 6, 2026-09-15)

Проблема (наблюдено): в старте thinking'а (после F-сброса буфера) строка мигает
одним словом (`∴ The`, `∴ Let`). Решение: порог 24 символа — до него строки нет.
- Бэкап: `cli.js.bak-preG-20260915`.
- G1 — OLD (1 вхождение): `if(s.length){let e=s.slice(-120)`
  NEW: `if(s.length>=24){let e=s.slice(-120)`
- G2 — флаг `__ltf` (P3a) на тот же порог, чтобы не рендерился пустой контейнер строки:
  OLD (1 вхождение): `typeof globalThis.__lt==="string"&&globalThis.__lt.length>0&&Date.now()-(globalThis.__ltt||0)<15000`
  NEW: `typeof globalThis.__lt==="string"&&globalThis.__lt.length>=24&&Date.now()-(globalThis.__ltt||0)<15000`
- Проверено: `node --check` OK, headless smoke `OK`. Коммит `220fd94` на `base`.

## H — stage PREFILL/THINKING/DECODE + tps в главной строке спиннера (итерация 7, 2026-09-16)

Решение (вариант B): без серверной части и без www.js — грубая клиентская
инференс-логика из уже имеющихся данных (`j6` = output-токены хода, `G` = thinking
статус). Три состояния: `j6<=0` → PREFILL; `G==="thinking"` → THINKING; иначе DECODE.
tps = `j6 / (now − первый токен)`, показывается только при elapsed ≥ 1000 мс.
`globalThis.__ft` — метка первого токена, сбрасывается на `message_start`.
Строка: `Befuddling… (2m 14s · ↓ 2.5k · DECODE 12 t/s)` — слово "tokens" убрано
(стрелка+число = токены, экономия ширины).
- Бэкап: `cli.js.bak-preH-20260916`.
- H1 — OLD (1 вхождение): `I6=nL(bm(tmz,emz,o6)),C6=[`
  NEW: вставить перед `C6=[` IIFE `__stg` (stage+tps, try/catch → null при ошибке).
- H2 — OLD (1 вхождение): `...f6&&s?[G==="thinking"&&!K?g5.createElement(k,{key:"thinking",color:I6},T6?`(${s})`:s):g5.createElement(k,{dimColor:!0,key:"thinking"},s)]:[]`
  NEW: `...f6&&__stg?[g5.createElement(k,{dimColor:!0,key:"stage"},__stg)]:[]`
  (цветной `thinking`/`thought for Ns` заменён на stage; `s`, `T6` остаются
  определёнными, просто не используются).
- H3 — OLD (1 вхождение): `G6," tokens"` → NEW: `G6`.
- H4 — F1-тап: `try{globalThis.__lt="";globalThis.__ltt=0}catch(e){}` →
  `try{globalThis.__lt="";globalThis.__ltt=0;globalThis.__ft=0}catch(e){}`.
- Проверено: `node --check` OK, headless smoke `ok`. Коммит `d0d705c` на `base`.
- Откат: `cp cli.js.bak-preH-20260916 cli.js`.
- Замечание: zsh history expansion съедает `!0` в `grep -cF '...!0...'` (даёт ложный 0);
  уникальность якорей проверять через `grep -oE ... | wc -l` или без `!` в паттерне.

## I — точные токены из API вместо оценки симв/4 (итерация 8, 2026-09-16)

Проблема: `↓ 2.5k` — это оценка `символы/4` (`responseLengthRef`, включает thinking-текст и
tool-JSON за весь ход), а не реальные токены → не сходится с сервером (124 ток.).
Решение (без www.js, только cli.js): брать точные значения из SSE-API:
- `message_start` → `usage.input_tokens` (точный input, доступен сразу на старте стрима);
- `message_delta` → `usage.output_tokens` (точный output, в конце сообщения).
Live decode-токены в стриме не приходят (проверено curl'ом: в `content_block_delta` нет usage)
→ live остаётся оценка симв/4, точное значение подставляется в конце.

- Бэкап: `cli.js.bak-preI-20260916`.
- I1 (message_start тап) — OLD (1 вхождение): `try{globalThis.__lt="";globalThis.__ltt=0;globalThis.__ft=0}catch(e){}`
  NEW: `try{globalThis.__lt="";globalThis.__ltt=0;globalThis.__ft=0;globalThis.__in=Y1.message?.usage?.input_tokens||0;globalThis.__st0=Date.now();globalThis.__out=0}catch(e){}`
- I2 (message_delta тап) — OLD (1 вхождение): `case"message_delta":{V6=iK6(V6,Y1.usage),T6=Y1.delta.stop_reason;`
  NEW: `case"message_delta":{try{if(Y1.usage&&Y1.usage.output_tokens)globalThis.__out=Y1.usage.output_tokens;globalThis.__end=Date.now()}catch(e){};V6=iK6(V6,Y1.usage),T6=Y1.delta.stop_reason;`
- I3 (G6 — число) — OLD (1 вхождение): `G6=mK(j6),`
  NEW: `G6=(globalThis.__out>0?mK(globalThis.__out):mK(j6)),` (в конце — точный output, иначе live-оценка j6).
- I4 (__stg — stage+tps) — OLD (1 вхождение): `__stg=(()=>{try{const now=Date.now();let st=j6<=0?"PREFILL":...`
  NEW: три ветки: `out>0` → `DECODE <точный tps> t/s` (tps = out/(end−ft));
  `!ft` (prefill) → `↑ <mK(__in)> PREFILL` (точный input); иначе → `THINKING`/`DECODE` + live tps.
- Проверено: `node --check` OK, headless smoke `ok`, debug-прогон: `in=4 out=17` (точные значения из API).
  Коммит `b61d762` на `base`.
- Откат: `cp cli.js.bak-preI-20260916 cli.js`.
- Ограничение: live decode-токены точными быть не могут без серверной части (стрим не шлёт
  usage в дельтах). MTP / LCP / KV-reuse клиенту недоступны (только в логах сервера / www.js).

## J — live /metrics поллер (MTP% + гейт) + стрелка по __ft (итерация 9, 2026-09-16)

Две проблемы:
1. Стрелка `↑/↓` вела себя от нативного `mode:q` (фаза assistant-сообщения), а stage —
   от `__ft` (время первого токена) → рассинхрон: `↑ 173 · DECODE` (стрелка prefill при
   декоде).
2. MTP-принятие (accepted/draft) клиенту недоступно из SSE, но llama.cpp отдаёт его в
   `/metrics` (Prometheus) — сервер включён с `--metrics`.

Решение (без www.js, только cli.js):
- **Стрелка**: в вызове `Kpz` передать `mode:globalThis.__ft?"responding":"requesting"` —
  `↑` когда `!__ft` (prefill), `↓` когда `__ft` (decode/thinking). Тот же сигнал, что и
  stage → рассинхрон невозможен.
- **Поллер** `globalThis.__mp` (IIFE, создаётся лениво в message_start тапе):
  - `setTimeout`-цепочка, период 500 мс; `timer.unref()` (процесс может выйти даже если
    таймер жив) + явный `clearTimeout` в `stop()` (остановка поллинга).
  - `fetch(origin+"/metrics", {signal: AbortSignal.timeout(500)})` — висящий fetch
    (сервер занят префилом) не блокирует; `origin` из `process.env.ANTHROPIC_BASE_URL`
    (хвостовые `/` срезаны).
  - `busy`-флаг: период (500 мс) < худшего fetch (500 мс таймаут) → без флага поллы
    перекрывались; ≤1 in-flight.
  - Парсинг Prometheus: `llamacpp:tokens_predicted_total`,
    `llamacpp:spec_decode_num_draft_tokens_total`,
    `llamacpp:spec_decode_num_accepted_tokens_total`, `llamacpp:requests_processing`
    (regex `^name(?:\{[^}]*\})?\s+(\S+)`, `parseFloat` — понимает `5.91435e+06`).
  - **Монотонность**: счётчики только растут; уменьшение = рестарт сервера →
    пере-базирование (`S.base[k]=d[k]`), дельта 0, никогда не отрицательная.
  - **MTP%**: `dDraft>0 ? (dAccepted/dDraft)*100 : null` (guard от деления на 0 →
    нет NaN/Inf).
  - **Гейт**: `requests_processing > 1` → `mtp=null` (сервер общий: supervisor + машина +
    субагенты; дельты server-wide, атрибуция на один запрос невозможна — без request-id).
  - **Старст/стоп**: `start()` на `message_start` (сброс base/last, очистка утекшего
    таймера, первый tick), `stop()` на `message_delta` (stop_reason). Все try/catch —
    тихий фолбэк: любой сбой поллера не ломает стрим.
- **Дисплей** (`__stg`): хелпер `mt` — ` MTP <round>%` если `__mp.last.mtp` конечен и
  свежий (`< 2500 мс`), иначе `""`; добавляется в обе DECODE-ветки (out>0 и live).

Анкеры (все 1 вхождение, проверено `grep -oE ... | wc -l`):
- J1 (стрелка): `g5.createElement(Kpz,{mode:q}` → `g5.createElement(Kpz,{mode:globalThis.__ft?"responding":"requesting"}`
- J2 (message_start тап → старт поллера): OLD `globalThis.__in=Y1.message?.usage?.input_tokens||0;globalThis.__st0=Date.now();globalThis.__out=0}catch(e){}` → NEW + полный поллер + `globalThis.__mp.start()`
- J3 (message_delta тап → стоп): OLD `globalThis.__end=Date.now()}catch(e){}` → NEW + `if(globalThis.__mp)globalThis.__mp.stop()`
- J4 (хелпер mt): OLD `end=globalThis.__end;let st;` → NEW + `const mt=(()=>{...})()`
- J5 (DECODE out>0): OLD `st+=" "+Math.round(out/(dec/1000))+" t/s"}else if(!ft){` → NEW `...t/s";st+=mt}else if(!ft){`
- J6 (live DECODE/THINKING): OLD `st+=" "+Math.round(j6/(el/1000))+" t/s"}}return st` → NEW `...t/s"}st+=mt}return st`

Проверено: `node --check` OK, headless smoke `ok`. Live-валидация по живому эндпоинту:
парсинг `pred=185100 draft=171021 acc=119553 proc=0`; симуляция дельты → **MTP 82.0%**
(совпадает с реальным логом сервера «Принято 82/100»); zero-draft guard → `null`
(нет NaN/Inf). Коммит `673c37f` на `base`.

Откат: `cp cli.js.bak-preJ-20260916 cli.js`.

Ограничение (честное): MTP% из /metrics — **server-wide** (суммарные счётчики сервера),
не per-request; при `requests_processing > 1` (параллельные запросы) строка MTP
скрывается гейтом. Per-request MTP/LCP/KV — только в логах сервера (www.js, не трогаем).

## K — фикс deadlock `__ft` (итерация 10, 2026-09-16)

Симптом (в живой сессии, бинарь J активен): `(35s · ↑ 176 · DECODE 125 t/s)` — стрелка
осталась ↑, число 176 заморожено.

Диагноз:
1. **`__ft` никогда не устанавливался** — deadlock. Единственная запись
   `if(!globalThis.__ft)globalThis.__ft=now` стояла в финальном `else`-ветке `__stg`,
   достижимой только когда `ft` (скопированный в начале IIFE `globalThis.__ft`)
   уже truthy. `__ft` стартует с 0 → ветка недостижима → `__ft` не ставится никогда →
   стрелка всегда ↑ (`mode` всегда "requesting"), а live-stage всегда "PREFILL"
   (ветка `!ft`) даже в декоде. Патч J1 (стрелка по `__ft`) был корректен, но читал
   переменную, которая не становилась truthy.
2. **176 — это `__out`, а не `__in`**. Число рядом со стрелкой — `G6` =
   `(globalThis.__out>0?mK(globalThis.__out):mK(j6))`. `__out` = точный
   `usage.output_tokens` из `message_delta` (конец сообщения). Наблюдение было в
   post-message состоянии (сообщение уже закончилось — stage "DECODE 125 t/s" из
   ветки `out>0`; 176 подтверждено транскриптом: `output_tokens:176` у сообщения
   перед наблюдением). Во время live-декода `G6 = mK(j6)`, где
   `j6 = D&&!D.isIdle ? D.progress?.tokenCount??0 : e+W` — live-счётчик, растёт.

Фикс (2 правки в `__stg` IIFE, обе анкеры count=1):
- K1: OLD `const now=Date.now(),out=globalThis.__out,ft=globalThis.__ft,st0=globalThis.__st0,end=globalThis.__end;`
  NEW `const now=Date.now(),out=globalThis.__out,st0=globalThis.__st0,end=globalThis.__end;let ft=globalThis.__ft;if(j6>0&&!ft){ft=now;globalThis.__ft=now}`
  — `__ft` ставится ДО ветвления, на первом рендере с `j6>0`. IIFE `__stg` выполняется
  раньше сборки `C6` (`})(),C6=[`) → стрелка видит свежий `__ft` в том же рендере.
- K2: OLD `if(j6>0){if(!globalThis.__ft)globalThis.__ft=now;const el=now-globalThis.__ft;`
  NEW `if(j6>0){const el=now-ft;` — мёртвая внутренняя запись убрана, `el` по обновлённому `ft`.

Поведение после фикса:
- PREFILL (`j6==0`): ↑, stage `↑ <in> PREFILL`.
- Первый рендер декода (`j6>0`): `__ft=now` → ↓, stage `DECODE`/`THINKING` (tps появится
  через ≥1 c), `G6 = mK(j6)` — растёт от 0.
- После конца сообщения: ↓, `G6 = mK(__out)` (точный output), stage `DECODE <tps> t/s`
  (ветка `out>0`) — остаётся до следующего `message_start` (stale, но консистентно).

Проверено: `node --check` OK, headless smoke `ok`. Коммит `2161933` на `base`.
Откат: `cp cli.js.bak-preK-20260916 cli.js`. Вступает в силу в новой сессии.

## L — event-driven SSE state machine (итерация 11, 2026-09-16)

Принцип: SSE-события — ЕДИНСТВЕННЫЙ источник истины для `__phase`, стрелки и
stage. `j6` — чисто презентационный счётчик (View), на фазу не влияет.
Убраны: поллер `globalThis.__mp` + все `fetch(.../metrics)`, хелпер ` MTP <n>%`,
`__ft`, `__st0`, эвристика фазы по `j6>0`.

Состояние (все на `globalThis`): `__phase` ("prefill"|"thinking"|"decode"),
`__in` (input_tokens из `message_start`), `__out` (output_tokens из
`message_delta`), `__t_decode` (момент первого decode-дельты), `__end` (момент
`message_delta`).

Хуки (ВАЖНО: два разных обработчика — `switch(Y1.type)` для message-level,
`switch(q.event.type)` для content-level; переменная события разная):
- L1 `message_start` (Y1.type): OLD
  `globalThis.__lt="";globalThis.__ltt=0;globalThis.__ft=0;globalThis.__in=Y1.message?.usage?.input_tokens||0;globalThis.__st0=Date.now();globalThis.__out=0;`
  NEW `globalThis.__lt="";globalThis.__ltt=0;globalThis.__phase="prefill";globalThis.__in=Y1.message?.usage?.input_tokens||0;globalThis.__out=0;globalThis.__t_decode=0;globalThis.__end=0;`
- L2 `message_start` (Y1.type): OLD — весь IIFE `if(!globalThis.__mp){...}globalThis.__mp.start()`
  (поллер /metrics, ~1.5 KB) → NEW пусто.
- L3 `message_delta` (Y1.type): OLD
  `try{if(Y1.usage&&Y1.usage.output_tokens)globalThis.__out=Y1.usage.output_tokens;globalThis.__end=Date.now();if(globalThis.__mp)globalThis.__mp.stop()}catch(e){}`
  NEW `try{globalThis.__out=Y1.usage?.output_tokens||0;globalThis.__end=Date.now()}catch(e){}`
- L4 `thinking_delta` (q.event.type): перед `}catch(e){};return;` добавить
  `if(globalThis.__phase==="prefill")globalThis.__phase="thinking";`
- L5 `text_delta` (q.event.type): OLD
  `case"text_delta":{let j=q.event.delta.text;_(j),w?.((H)=>(H??"")+j);return}`
  NEW — перед `return}` добавить
  `if(globalThis.__phase!=="decode"){globalThis.__phase="decode";if(!globalThis.__t_decode)globalThis.__t_decode=Date.now()}`
- L6 `input_json_delta` (q.event.type): то же decode-переход вставить перед
  финальным `return}` кейса.

Рендер (функция `r1K`, 4 правки):
- L7 `__stg` IIFE целиком: OLD (ветки по `ft`/`out`/`G==="thinking"` + `mt` MTP)
  NEW `__stg=(()=>{try{const ph=globalThis.__phase||"prefill";let st;if(globalThis.__out>0){const dt=((globalThis.__end||Date.now())-globalThis.__t_decode)/1000;const tps=dt>0.1?Math.round(globalThis.__out/dt):0;st="DECODE "+tps+" t/s"}else if(ph==="prefill"){st="PREFILL"}else if(ph==="thinking"){st="THINKING"}else{const dt=(Date.now()-globalThis.__t_decode)/1000;const tps=dt>0.1?Math.round(j6/dt):0;st="DECODE "+tps+" t/s"}return st}catch(e){return null}})()`
- L8 `G6`: OLD `G6=(globalThis.__out>0?mK(globalThis.__out):mK(j6)),`
  NEW `G6=(globalThis.__phase==="prefill"?mK(globalThis.__in):(globalThis.__out>0?mK(globalThis.__out):mK(j6))),`
  — в PREFILL число = `__in` (input tokens), в DECODE live = `j6`, после
  `message_delta` = точный `__out`.
- L9 стрелка: OLD `g5.createElement(Kpz,{mode:globalThis.__ft?"responding":"requesting"})`
  NEW `g5.createElement(Kpz,{mode:globalThis.__phase==="prefill"?"requesting":"responding"})`
- L10 гейты (иначе строка не рендерится в чистом prefill, где `j6==0` и `G==null`):
  OLD `A6=G!==null,J6=M||P||i>smz,X6=X-n-5,f6=A6&&X6>a`
  NEW `A6=G!==null,J6=M||P||i>smz,X6=X-n-5,f6=(A6||globalThis.__phase)&&X6>a`
  OLD `V6=N6+(Z6?M6+l:0),y6=J6&&j6>0&&X6>V6+o`
  NEW `V6=N6+(Z6?M6+l:0),y6=((J6&&j6>0)||globalThis.__phase)&&X6>V6+o`

Поведение:
- PREFILL: `↑ <in> · PREFILL` (стрелка requesting, число = input tokens).
- THINKING: `↓ <j6> · THINKING`.
- DECODE live: `↓ <j6> · DECODE <tps> t/s` (tps по `__t_decode`, `j6` — оценка).
- После `message_delta`: `↓ <out> · DECODE <tps> t/s` (точный `__out`, точный tps
  по `__end - __t_decode`).

Проверено: `node --check` OK; grep: `globalThis.__mp`=0, `globalThis.__ft`=0,
`__st0`=0 (остаточные `/metrics` — нативный код Anthropic API/OTLP, не патч);
headless smoke `ok`. Коммит `2dfef5d` на `base`.
Откат: `cp cli.js.bak-preL-20260916 cli.js`. Вступает в силу в новой сессии.

## M-1..M-9 — доитерации (2026-09-16/17, коммиты после L)
- `f006b12` — reset фазы на отправке запроса (prefill), `__in` только в `message_start`, убран temp stream-debug.
- `197c6a7` — фаза-машина в compact-fork (`hG`): статус не застревает в PREFILL при компакции.
- `165d45a` — live-оценка `__out` в compact-fork (chars/4 per text_delta).
- `73ebe7c` — `mK` всегда k-нотация (787 → 0.8k).
- `26d0a64` — статус-строка: только фаза (PREFILL/THINKING/DECODE), без t/s.
- `ae37b85` — `__in=0` при reset на отправке (NaNk в prefill до `message_start`).
- `147db7b` — `__in` оценивается из запроса в точке отправки (prefill показывает ~input tokens).
- `2495309` — фаза-машина + `__lt`-тап в MAIN PATH (`P7`/`L1` handler, thinking/text/input_json дельты) — live THINKING/DECODE и `∴` в обычных ходах. **Именно этот коммит добавил второй append в `__lt` (см. M).**
- `bc2b07e` — `∴` сниппет держится, пока `__phase==="thinking"` (пропади на медленной модели); `mK` возвращён к стоковому (raw <1000, k ≥1000).

## M — фикс дублирующего тапа `__lt` (итерация 12, 2026-09-17)

Симптом: в интерактивных сессиях `∴`-сниппет мусорил lockstep-дублированием
(`еслиесли`, `CLECLEANAN`, `review_ver_verdictdict`) — каждый чанк дельты
дублировался.

Диагноз: в бандле ДВА обработчика `thinking_delta` дописывали в `globalThis.__lt`:
- Tap 1 — `q.event`-уровень (из P1);
- Tap 2 — main path `P7`/`L1` (из `2495309`).
В интерактиве срабатывают ОБА → каждая дельта добавляется дважды → lockstep-дубль.
Headless-проба (stderr-счётчики): t1=0, t2=430, буфер чистый при одном тапе →
headless бьёт только Tap 2. Модель исключена: в сессионном логе все
«сломанные» строки — цитаты пользовательского паста, спонтанного гарибля в
thinking/text блоках нет.

Фикс: из Tap 1 удалён append в `__lt`; оставлен только идемпотентный
`__phase`-переход `prefill→thinking` (защита compact-fork, `197c6a7`).
Tap 2 — единственный источник буфера (работает и в интерактиве, и в headless).

Проверено: grep — append-сайтов `__lt` = 1; `node --check` OK; headless smoke `ok`.
Коммит `12d0e9c` на `base`.
Откат: `cp cli.js.bak-preM-20260917 cli.js`. Вступает в силу в НОВОЙ сессии
(бинарь читается на старте процесса).

## Процедура (строго по шагам)
1. `cd /home/hermes/git/claude-code-2.1.88`
2. Бэкап: `cp cli.js cli.js.bak-20260915`
3. Повторная проверка уникальности (ожидаем 1 и 1):
   - `grep -cF 'case"thinking_delta":_(q.event.delta.thinking);return;' cli.js`
   - `grep -cF 'p?`Next: ${p.subject}`:`Tip: ${J6}`' cli.js`
4. Применить P1, затем P2 (Edit tool, точные строки выше).
5. `node --check cli.js` (синтаксис).
6. Headless smoke (сервер 192.168.8.131:8080):
   ```
   ANTHROPIC_BASE_URL=http://192.168.8.131:8080 ANTHROPIC_AUTH_TOKEN=local-dummy \
   ANTHROPIC_API_KEY= ANTHROPIC_MODEL=Qwen3.8-27B-MTP \
   claude -p "reply with exactly: ok"
   ```
   Ожидаем `ok`.
7. Интерактивный тест в НОВОЙ сессии: запрос, вызывающий thinking; проверить:
   - во время thinking строка `∴ <сниппет>` обновляется;
   - через >15 c после окончания thinking — возврат к обычной Tip;
   - tool-вызовы и обычный стриминг текста работают как раньше.
8. Только после успешного теста — рабочая сессия на patched CLI.

## Откат
`cp cli.js.bak-20260915 cli.js` (одна команда, без перезапуска чего-либо — бинарь
читается на старте процесса).

## Риски
- Минифицированный бандл: синтаксическая ошибка → CLI не стартует → видно сразу, откат.
- Runtime-особенности: try/catch в обеих точках → при любом исключении fallback на
  оригинальное поведение.
- Blast radius: supervisor + машина (машина не видит изменения — thinking выключен).
- `DISABLE_AUTOUPDATER=1` — патч не улетит под автообновлением.
- Память: буфер ограничен 800 байт.

## Не делаем
- Не трогаем `stanok/` (машина), transcript, OTel.
- Settings: только `spinnerTipsEnabled: false` (P3), остальное не трогаем.
- Не делаем MITM-прокси, не пересобираем CLI из source/.
