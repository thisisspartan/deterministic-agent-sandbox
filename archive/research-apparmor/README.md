# archive/research-apparmor — закрытая research-линия X1a (rev1–rev14)

Закрыто оператором 2026-10-10 («заканчиваем с Rev14»); решения K8s — `specs/SPEC-STANOK-K8S-RUNTIME-2026-10-10.md`.
VM-прогон rev14 не выполнялся. Модель трёх профилей осталась ПРЕДВАРИТЕЛЬНО принятой, эмпирически
не проверенной. Живые находки в силе: X1 (bwrap невозможен с обычными профилями), X4-gap
(закрыт Fresh-check), bwrap 0.8.0 в pinned-образе.

Протоколы прогонов: `specs/X1A-R4.2-RUN1-2026-10-10.md`, `specs/X1A-R4.2-RUN2-2026-10-10.md`,
результаты RUN2: `specs/x1a-run2-results/`. История ревизий и все отменённые пины:
`specs/SPEC-X1A-MANAGED-PROFILES-2026-10-09.md`, `CONTEXT.md` (session log 2026-10-09..10).

## Финальные пины (SHA-256, сверены с файлами этого каталога 2026-10-10)

| артефакт | файл | SHA-256 |
|---|---|---|
| профиль (три профиля, rev13b) | `rev13/stanok-x1a-test.apparmor` | `420505ed30ec7f6df094a27f217dc677574cc0d37cd8ee3287ae6f71c5b3f129` |
| seccomp | `v-cli3.json` | `480ebf2322a9151a08dc5b64a253ba25b7e2e0b94f0bc90b676285d41c0de997` |
| W7 probe | `rev13/w7-probe.py` | `e22d0314143774166c71dfc0332defd5eda6c7085da46c492a741e1088a0baeb` |
| W-matrix harness | `rev13/w-harness.py` | `ee0e886dd8927ad24f711817eabaaaa535fb852c83708a52acfb1f4f00539ff5` |
| sandbox probe | `rev13/w-probe.py` | `7164704e62938046571c257d30d91575d8dfce4d9e6f63bb1aff9dc38c343415` |
| тест-скрипт (rev14) | `x1a-test.sh` | `63f694755d67495a24af4c29bc14021795c1778c82f4ad277c128744a0115260` |
| VM-оркестратор | `vm-run.sh` | `ed4b2d58902cd194071ea557e1e98d5fdb41d5308097e95c935ba4fdfd857ef6` |
| cloud image (не в архиве) | /var/tmp/x1a-vm/noble-server-cloudimg-amd64.img | `6a81c37564db9b1ee84e141922625e1d7c5b389b99bb3c572e0243607d5bb4d2` |
| Docker image (не в архиве) | stanok-machine:latest | `sha256:913ad405b48948ab3c31d0222774163a65ad083b0c3541d8303be39380f5b15c` |

## Состав

- `rev13/` — финальные профили и probes/harness (rev13b/rev14); синтаксические зонды парсера.
- `x1a-test.sh`, `vm-run.sh` — скрипты rev14 (запуск не выполнялся).
- `a8-harness.py`, `a8-probe.py` — отложенный harness rev12 (латентные дефекты P2/P4/P5/P6
  исправлены в `rev13/w-probe.py`).
- `stanok-bwrap-x1a-test.apparmor`, `stanok-bwrap.apparmor`, `bad-profile.apparmor` —
  промежуточные профили rev2–rev12 и fixture статической проверки.
- `v-cli*.json`, `seccomp-stanok.json` — эволюция seccomp-политики (финаль — v-cli3.json).
- `bubblewrap-0.8.0*.c`, `bubblewrap.c`, `bind-mount.c`, `namespace.c`, `super.c`,
  `root.c`, `fs_context.*`, `user_namespace.c`, `utils.c` — аудированные исходники
  (bubblewrap v0.8.0, kernel v6.8) — доказательная база mount-правил.
- `mcheck.awk` — статическая проверка семантики mount-правил; `parsed.out/.err`,
  `parse-selftest.err`, `profiles.zip`, `github.com/` — артефакты parse-check и загрузки.
