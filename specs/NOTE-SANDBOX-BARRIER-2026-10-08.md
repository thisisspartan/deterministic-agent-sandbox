# NOTE: один барьер или два (item 4 из внешнего обзора CC-214) — ОТЛОЖЕНО, решение оператора

Дата анализа: 2026-10-08. Статус: зафиксировано, обсуждение позже. Никаких кодовых
изменений, тикетов и прогонов не делалось.

## Вопрос
Docker-контейнер (барьер 1) + вложенный bwrap-песочница Claude Code внутри контейнера
(барьер 2, `settings.stanok.json: sandbox.enabled=true`). В прогоне cc214-wt барьер 2
сломал каждый Bash-вызов; машина отчиталась «Tests: PASS», не выполнив тестов.

## Что каждый барьер обеспечивает сегодня (проверено по коду)

| Ограничение | Контейнер | Вложенный bwrap |
|---|---|---|
| запись вне src/tests/docs/scripts | ✅ base `:ro` + carve-outs (`launcher/sandbox.py:61-65`, CC-154) | дублирует |
| `../evidence ../hooks ../launcher ../.claude` (deny в settings.stanok.json) | ✅ parent-dir `:ro` mount | дублирует |
| `/tmp/stanok-logs` deny | ✅ не смонтирован в контейнере | дублирует (пусто) |
| `.claude/settings*.json`, `.git/hooks`, `.git/config` | ✅ наследуют base `:ro` | built-in deny cli.js (offset 4379653, безусловный) |
| сеть (allowedDomains) | ❌ `--network=host` | ✅ единственная уникальная функция барьера 2 |
| seccomp unix-socket block | ❌ | ✅ маргинально |

## Режим отказа барьера 2 (инцидент CC-214, evidence/cc214-wt)
cli.js безусловно добавляет `.claude/settings.local.json` в deny-лист (самозащита
permissions). bwrap bind'ит `/dev/null` поверх deny-пути; для несуществующего файла
создаёт mount point → внутри контейнера `.claude/` = `:ro` → EROFS → отказ каждого
Bash-вызова. В свежем worktree файла нет (gitignored) — сломался именно worktree-прогон;
в главном дереве файл существует, bind проходит. Настройками не лечится: deny built-in;
`enableWeakerNestedSandbox` (cli.js offset 4348420: `if(!j) --proc /proc`) решает только
`--proc`; `failIfUnavailable` (FC_) проверяет наличие бинарников, per-call EROFS не ловит —
молчаливый отказ при rc=0.

## Нативные примитивы (cli.js 2.1.88, §7)
- `sandbox.enabled` → `AT8`/`wT8`: `false` полностью отключает обёртку (`Y54`:
  `if(!_&&!f&&!G) return K`). Штатный выключатель.
- `enableWeakerNestedSandbox` (`k54` → `Y54.j`): вложенный режим, пропускает `--proc`
  (у нас уже `true`).
- Примитива отключить built-in deny settings-файлов — нет.

## История
Барьер 2 введён в `984eb7d` (B1 hybrid, 2026-09-18): тогда контейнер ещё не монтировал
base `:ro` (CC-154 позже) — deny-записали имели смысл. После CC-154 избыточны; уникальным
остался только сетевой allowlist. Ради bwrap-внутри-Docker уже добавлен хостовый обход
(tmpfs per-uid tmp dir, `sandbox.py:116-125`).

## Рекомендация (не принята)
Один барьер: `settings.stanok.json: sandbox.enabled: false`. Согласует конфиг с машинным
CLAUDE.md («the boundary is the container, not the command»). Теряется сетевой allowlist;
варианты: (a) принять host-сеть; (b) изоляция на стороне контейнера (`--network=none` +
прокси) — новый механизм, требует отдельного решения.

## Открытые вопросы для обсуждения
1. Нужен ли сетевой allowlist как класс защиты (эксфильтрация) или угроза только в записях?
2. Если да — где он должен жить: bwrap или контейнер?
3. item 1 внешнего обзора (seed `.claude/settings.local.json` в worktree) — workaround,
   нужный только если барьер 2 остаётся.
