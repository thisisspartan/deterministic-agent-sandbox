# TASK-STANOK-CC-049 — INFRA-01 + SEC-03: стабилизация и shift-left malware-scan

Статус: `[x] DONE` (выполнено супервайзером на хосте — инфраструктурные правки, не код проекта)

## INFRA-01 (onboarding/стабильность)

1. `setup.sh` — установка commit-msg хука через `git rev-parse --git-path hooks`
   (работает и в сабмодуле, где `.git` — файл, а не каталог).
2. `hooks/doctor.sh:25` — тот же фикс: проверка commit-msg хука через `--git-path hooks`.
3. `CLAUDE.md` (роль станка) — шаг 3: явная команда smoke `bash scripts/run.sh smoke src/<module>.js`.
4. `git rm hooks/domain-allowlist.sh` — мёртвый хук (нет в settings, WebFetch не в allow).
5. `launcher/stanok.py` — удалена ветка `--background` (Popen self-respawn):
   background-режим принадлежит host-side `launch.sh` (nohup); внутри bwrap
   self-respawn обошёл бы lock и host-гейты.
6. `launch.sh` — usage-строка без `[-- extra...]` (разбор `--` сохранён).
7. README-синхронизация: `stanok/README.md` (14 ok, список хуков, fail-closed dirty-tree,
   malware-scan PreToolUse) и `skeleton-pub/README.md` (14 ok, env-список без STANOK_LAUNCHER).

## SEC-03 (shift-left malware-scan)

1. `hooks/malware-scan.sh` переписан: PostToolUse → **PreToolUse** (deny ДО записи на диск).
   - Write: буфер = `tool_input.content`.
   - Edit: виртуальный буфер = `content.replace(old, new, 1)` (защита от сплита пейлоада).
   - Правила deny: (a) чувствительные env (KEY|TOKEN|SECRET|PASS|CRED|AUTH) + канал;
     (b) голый `process.env` + канал; (c) obfuscation (`atob`, `Buffer.from(...,'base64')`);
     (d) в `tests/` любой канал = deny сам по себе.
   - Канал: `require('child_process|net|http|https|dgram')` или `\b(eval|new Function|exec|spawn|fork)\b`.
   - Формат deny: `hookSpecificOutput` (permissionDecision=deny), exit 0.
   - Аудит: `evidence/malware-scan/flags.log`.
2. `.claude/settings.stanok.json` — malware-scan в PreToolUse (Write|Edit);
   PostToolUse остался только verifier.sh.

## Смоки (ЭТАП 3)

- `bash setup.sh` → SETUP-OK
- `DOCTOR_EXPECT_NO_CLOUD=1 bash hooks/doctor.sh` → 14 ok, 0 fail
- Write src с `process.env.API_KEY` → DENY (SMOKE-SRC-DENY-OK)
- Write tests с `require("http")` → DENY (SMOKE-TESTS-DENY-OK)
- Легитимный `process.env.TERM` → ALLOW (SMOKE-LEGIT-ALLOW-OK)
- `bash scripts/run.sh test tests/rng.test.js` → PASS
