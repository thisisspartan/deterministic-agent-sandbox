# TASK-WWWJS-02: Панель NGRAM-MOD (второй источник спекуляции)

Supervisor-executed (www.js на 192.168.8.131, не машина).

## Проблема

Статистика `I spec common_specu: statistics ngram-mod: #calls(b,g,a) = ...,
#gen drafts = N, #acc drafts = N, #gen tokens = N, #acc tokens = N,
#mean acc len = N.N, #acc rate/pos = (64 значения), ...` не отображается —
дашборд видит только draft-mtp.

## Изменения (~/www.js)

1. State: `ngram: { accTokens: 0, genTokens: 0, meanLen: 0, posAcc: [] }`.
2. Парсер: ветка `line.includes('statistics ngram-mod:')` → извлечь
   `#acc tokens`, `#gen tokens`, `#mean acc len`, кортеж `#acc rate/pos`.
   (Строки `statistics draft-mtp:` и per-task `acc per pos` НЕ трогают ngram.)
3. UI: карточка под MTP-панелью: `NGRAM-MOD SPEC` + строка
   `<acc>/<gen> ток. (NN%) | mean N.NN ток/такт`.

## Acceptance

- Локальный тест: реальная ngram-mod строка → state.ngram заполнен
  (accTokens/genTokens/meanLen/posAcc.length == 64); draft-mtp строка
  ngram не меняет.
- Live: HTTP 200, в served HTML есть блок NGRAM-MOD; после реального
  запроса /api/state несёт ngram.accTokens > 0.
