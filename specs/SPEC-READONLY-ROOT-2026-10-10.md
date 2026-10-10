# SPEC-READONLY-ROOT-2026-10-10 — readOnlyRootFilesystem для worker/fresh Pod'ов (CC-229)

## Мотивация
Package 1 явно исключил readOnlyRootFilesystem (scope-ограничение оператора).
Отложенный пункт закрывается отдельным тикетом с live-прогоном.

## Факты grilling (2026-10-10, проверено по коду)
- Worker-Pod: `pod_runner.py:93-105` ре-направляет `TMPDIR`/`CLAUDE_TMPDIR`/`HOME`
  в `/stanok-work` (emptyDir); репозиторий — `/stanok-work/repo`, логи —
  `/stanok-work/logs`; `PYTHONDONTWRITEBYTECODE=1`. Все остальные mounts `:ro`.
- Fresh-Pod: распаковка дерева, `git apply` и тесты — только в `/stanok-work`
  (emptyDir). `__pycache__` — внутри дерева (emptyDir).
- Вывод: оба Pod'а уже не пишут в корневую ФС → readOnlyRootFilesystem
  реализуем БЕЗ новых volume'ов.

## Требования
1. `k8s/worker-job.yaml.tmpl` и `k8s/fresh-job.yaml.tmpl`: в container
   `securityContext` добавить `readOnlyRootFilesystem: true` (рядом с
   allowPrivilegeEscalation/capabilities/seccomp).
2. Пины в `launcher/tests_harness/test_k8s_manifests.py`: оба шаблона содержат
   `readOnlyRootFilesystem: true` (regex/substring-пин, стиль существующих).
3. Ничего больше не меняется (ни volume'ов, ни NetworkPolicy, ни Docker/bwrap
   legacy-пути).

## Acceptance criteria
- Харнесс на чистом дереве: все тесты PASS (пин +2), ноль регрессий.
- Live-приёмка (machine-тикет CC-229, тривиальная задача): worker-Pod работает
  под read-only root — rc=0, verifier PASS, contract clean, fresh Job green;
  ни одного EROFS/Read-only file system в errors/failures.
- Любая EROFS-находка в живом прогоне — дефект среды (не тикета): фиксируется
  в CONTEXT.md, путь-источник добавляет volume/редирект, повторный прогон.

## Scope
- НЕ трогать: NetworkPolicy, disk bounds, legacy Docker/bwrap путь.
