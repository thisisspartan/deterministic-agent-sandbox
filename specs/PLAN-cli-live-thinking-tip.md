# PLAN: live thinking в строке Tip спиннера (patch cli.js)

Статус: **PASS 2026-09-15 (итерация 6: P1+P2+P3+A+E+F+G).** `node --check` OK, headless smoke OK,
интерактивный тест P1+P2 пройден (сессия PID 2697524; `∴` live-сниппет виден,
tool-стриминг не сломан). P3 (tips off) применён + `spinnerTipsEnabled: false` в
`~/.claude/settings.json`. A (хвост буфера вместо последней строки) применён —
вступит в силу после рестарта/резюма сессии. Статус-лайн `statusline-thinking.sh`
отключён из settings (redundant: не live, дублирует спиннер) — тоже после рестарта.
Откаты: G → `cp cli.js.bak-preG-20260915 cli.js`; F → `cp cli.js.bak-preF-20260915 cli.js`; E → `cp cli.js.bak-preE-20260915 cli.js`; A → `cp cli.js.bak-preA-20260915 cli.js`;
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
