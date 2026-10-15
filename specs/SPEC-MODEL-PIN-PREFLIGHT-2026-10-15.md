# SPEC-MODEL-PIN-PREFLIGHT (CC-266, host-side) — 2026-10-15

Источник: внешний аудит от `332cf9b`/`da8090a`, открытая линия «модель не фиксируется»:
preflight проверяет доступность сервера и `n_ctx` (rc=20), но не идентичность модели —
запуск с другим сервером/моделью молча проходит. Решение оператора 2026-10-15: переводим
в работу (host-side, без machine-тикета; SPEC-HOSTSIDE-WORKFLOW).

## Факты (проверены 2026-10-15)

- `gates.preflight_server` (gates.py:314): GET `{server_url}/props` → проверка `n_ctx`;
  `STANOK_SKIP_SERVER_CHECK=1` пропускает всё; отказ → rc=20.
- Живой `/props` (192.168.8.131:8080) отдаёт `model_alias` (ровно `qwen3.8-flash-next-iq3_xxs`
  = `DEFAULT_MODEL`, config.py:22) и `model_path`; llama-server additionally отдаёт
  `model_path_aliases` в других сборках.
- `cfg.model` (`STANOK_MODEL`) передаётся в Pod (k8s.py:862) как имя для API-запроса;
  сервер его не сверяет — идентичность нигде не проверяется.
- `STANOK_TEMP`: потребитель — патченный cli.js (`~/git/claude-code-2.1.88/cli.js`,
  `process.env.STANOK_TEMP` → temperature API-запроса; коммит `de1d35c`). Не мёртвая
  настройка; документировать в `patches/PATCHES.md` (линия cli.js, CC-143).

## Требования

- R1. `preflight_server` после получения `/props` сверяет `cfg.model` с идентичностями
  сервера: `model_alias`, элементы `model_path_aliases`, basename `model_path` без
  расширения. Совпадение — case-insensitive точное равенство хотя бы одной.
- R2. Нет ни одной идентичности в `/props` → fail-closed, rc=20 (сервер не говорит,
  что он за — не гадаем).
- R3. Несовпадение → rc=20, лог `PREFLIGHT: server model ... != configured STANOK_MODEL ...`.
- R4. `STANOK_SKIP_SERVER_CHECK=1` сохраняет полный пропуск (включая model-проверку).
- R5. Новый rc не вводится (переиспользуется 20 = server-side preflight-отказ).
- R6. `patches/PATCHES.md`: раздел о cli.js-линии — STANOK_TEMP → temperature (патченный
  cli.js, вне дерева; контракт documented, код не меняется).

## Acceptance

- Hermetic-тесты (monkeypatch `_fetch_server_props`): совпадение по alias → True;
  case-insensitive → True; несовпадение → False + текст лога; пустая идентичность →
  False + «no model identity»; совпадение по `model_path_aliases` и по basename
  `model_path` → True. Существующие preflight-тесты (window-деривация) остаются зелёными.
- Doctor зелёный.

## Не делаем

- Не фиксируем модель в Pod-транспорте (имя и так доезжает; проверяется сервер).
- Не трогаем STANOK_TEMP в коде (потребитель — cli.js вне репо).
