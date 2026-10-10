# X1a R4.2 — RUN1 (2026-10-10, rev8): FAIL на A7-strict, локализовано

Итог: A7-strict rc=1 (`bwrap: Failed to make / slave: Permission denied`), стоп без
расширения разрешений; A7-weaker/A8 не выполнялись. Оба временных профиля сняты
(CLEANUP-OK в run.log; в kernel-логе profile_remove ×2). Production не затронута.

## Диагностика (kernel audit, journalctl -k, 00:34:20)

```
apparmor="DENIED" operation="mount" class="mount" info="failed flags match" error=-13
  profile="stanok-bwrap-x1a-test" name="/" pid=2803177 comm="bwrap" flags="rw, silent, rslave"
```

Подтверждено: блокируется именно смена распространения mount (`MS_SLAVE|MS_REC`,
bwrap main.c `make_propagation_slave()`: `mount(NULL,"/",NULL,MS_SILENT|MS_SLAVE|MS_REC,NULL)`)
для `/`. AppArmor нормализует вызов во flags `rw, silent, rslave`; правило `remount /`
эту комбинацию не покрывает. Причина-diagnosis оператора подтверждена логом.

## Исправление (rev9)

- Профиль: добавлено узкое exact-match правило `mount options=(rw, silent, rslave) -> /,`
  (только на `/`; общего `mount` нет). Вариант `options=rslave` без rw/silent не совпал бы
  с exact-match. Грамматика токенов подтверждена по apparmor.d(5) (`silent`, `rslave` —
  допустимые флаги). `apparmor_parser -Q -K` зелёный.
  Новый пин профиля: `128901bd8683bd53050b73f56f5bda55681be1defaba8748fe47f1ad085d2a47`
  (старый `59ada146…` отменён).
- Скрипт: пин профиля обновлён; захват `dmesg | grep -i apparmor` перенесён в cleanup()
  (сохраняется и на FAIL-путях; в run1 секция 10 до FAIL не дошла).
  Новый пин скрипта: `13ffdb532332cd2eac433cf4451a339a1b67a51a747bb6f024c79e8c3f3a4b9d`
  (старый `449ae4db…` отменён; `sh -n` зелёный).

## Факт хоста (процедурный)

`/run` смонтирован **noexec** (tmpfs, `rw,nosuid,nodev,noexec`): прямой
`sudo /run/x1a-test/x1a-test.sh` → `sudo: unable to execute … Permission denied`.
Запуск: `sudo /bin/sh /run/x1a-test/x1a-test.sh` (guard `$0` это допускает).

## Ход run1 (run.log)

Все входные хэши сверены OK; image ID OK; kernel preconditions OK; parse OK;
профили загружены; A7-strict FAIL → STOP; CLEANUP-OK ×2.
Артефакты: `/run/x1a-test/results/` (run.log, a7-strict.out; dmesg-запись пуста —
секция 10 не выполнена; аудит выше взят из journalctl оператором/супервизором).

## Значение

Отказ — конкретная первая mount-операция, не опровержение модели изоляции.
Следующий эксперимент (rev9) локализует: проходит ли bwrap setup с exact-match
rslave-правилом; при новом FAIL — та же процедура (стоп, без расширения, снять профили).
