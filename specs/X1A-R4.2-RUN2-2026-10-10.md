# X1a R4.2 — RUN2 (2026-10-10, rev9): FAIL на A7-strict, локализован (tmpfs srcname)

Итог: A7-strict rc=1 (`bwrap: Failed to mount tmpfs: Permission denied`), стоп без
расширения разрешений; A7-weaker/A8 не выполнялись. Оба временных профиля сняты
(CLEANUP-OK в run.log; profile_remove ×2 в dmesg-захвате — новая возможность rev9
сохраняет аудит и на FAIL-путях). Production не затронута.

Прогресс против run1: rslave-правило из rev9 сработало — bwrap прошёл
`make / slave` и упал на следующей операции (mount tmpfs в /tmp).

## Диагностика (kernel audit, dmesg-захват результатов run2)

```
apparmor="DENIED" operation="mount" class="mount" info="failed srcname match" error=-13
  profile="stanok-bwrap-x1a-test" name="/tmp/" pid=2877169 comm="bwrap"
  fstype="tmpfs" srcname="tmpfs" flags="rw, nosuid, nodev"
```

`info="failed srcname match"`: правило `mount fstype=tmpfs /tmp,` интерпретируется
по грамматике apparmor.d(5) как `MOUNT = [QUALIFIERS] [SOURCE FILEGLOB] ['->' [MOUNTPOINT FILEGLOB]]`
— путь без `->` это ИСТОЧНИК (устройство), а не точка монтирования. Ядро подставляет
srcname="tmpfs" (имя источника tmpfs-монтирования), путь `/tmp/` в правиле стоял на
позиции SOURCE → несовпадение. Точка монтирования задаётся только после `->`.

Грамматика подтверждена по man apparmor.d(5): `REMOUNT`/`UMOUNT` принимают MOUNTPOINT
напрямую (без `->`) — существующие remount/umount-правила корректны и не менялись.

## Исправление (rev10)

- Профиль: четыре fstype-правила переписаны в форму `mount fstype=X -> <mountpoint>,`
  (/tmp, /newroot/dev, /newroot/dev/pts, /newroot/proc); bind-правила уже имели `->`;
  rslave/exact-match правило не менялось; разрешения не расширены.
  Новый пин профиля: `06fc2e51ecae545f2a66a16f2c382dcefbaa6556ef894e919fd5e2b35dc7436c`
  (старый `128901bd…` отменён; `apparmor_parser -Q -K` зелёный).
- Скрипт: добавлена статическая проверка семантики mount-правил (после parse-check):
  awk отвергает любую строку `mount …` без `->` (remount/umount/comments/pivot_root не
  матчатся); несовпадение = abort до загрузки профилей. Проверка прогнана независимо:
  на rev10-профиле проходит, на синтетическом bad-правиле даёт ненулевой rc и помечает
  только bad-строку.
  Новый пин скрипта: `77fa3c58596ab0b8598e74f0903451ca72fb522f0f75ca2e3f5ea70d81e35140`
  (старый `13ffdb53…` отменён; `sh -n` зелёный).

## Ход run2 (run.log)

Все входные хэши сверены OK (профиль 128901bd… — rev9); image ID OK; kernel
preconditions OK; parse OK; профили загружены; A7-strict FAIL → STOP; CLEANUP-OK ×2.
Артефакты: `/run/x1a-test/results/` (run.log, a7-strict.out, dmesg-apparmor.txt —
содержит записи обеих попыток: kernel-времена 51425=run1, 51975=run2); архив
без root: `specs/x1a-run2-results/` (доступ открыт cleanup(): traversal + чтение).

## Значение

Отказ — вторая конкретная mount-операция, локализованная до уровня семантики
грамматики (не модели изоляции). rev10 меняет только форму правил (source/mountpoint),
объём разрешений идентичен rev9. Следующий эксперимент (rev10) проверяет прохождение
bwrap setup с корректными mountpoint-правилами; при новом FAIL — та же процедура
(стоп, без расширения, снять профили).
