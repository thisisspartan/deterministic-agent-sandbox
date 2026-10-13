# RUNBOOK — эксплуатационные процедуры

## Восстановление gVisor-рантайма после пересборки ноды (требует root)

Дефолт runtime-класса = gvisor (CC-256). После пересборки ноды `runsc` и
RuntimeClass `gvisor` отсутствуют → запуск падает на preflight с rc=16
(подсказка: создать RuntimeClass или `STANOK_K8S_RUNTIME_CLASS=runc`).

1. Установка runsc (root):
```bash
cd /tmp
curl -fsSLO https://storage.googleapis.com/gvisor/releases/release/latest/x86_64/runsc
curl -fsSLO https://storage.googleapis.com/gvisor/releases/release/latest/x86_64/containerd-shim-runsc-v1
sudo install -m 0755 runsc containerd-shim-runsc-v1 /usr/local/bin/
runsc --version
```
2. Регистрация в containerd k3s (root) — шаблон
`/var/lib/rancher/k3s/agent/etc/containerd/config-v3.toml.tmpl`:
```toml
{{ template "base" . }}

[plugins.'io.containerd.cri.v1.runtime'.containerd.runtimes.'runsc']
  runtime_type = "io.containerd.runsc.v1"
```
`sudo systemctl restart k3s`; проверка: `kubectl get nodes` Ready,
`grep -A2 runsc /var/lib/rancher/k3s/agent/etc/containerd/config.toml`.
(legacy config version 2 → `config.toml.tmpl` с
`[plugins."io.containerd.grpc.v1.cri".containerd.runtimes.runsc]`.)
3. RuntimeClass (root не нужен, kubectl):
```yaml
apiVersion: node.k8s.io/v1
kind: RuntimeClass
metadata: {name: gvisor}
handler: runsc
```
4. Живая проверка: `kubectl get runtimeclass gvisor`; netpol-smoke без knob →
17/17, probe-Pod'ы `.spec.runtimeClassName=gvisor` (API read-back).

## Штатный аварийный откат (root не нужен)

`STANOK_K8S_RUNTIME_CLASS=runc` → поле `runtimeClassName` не рендерится
(RuntimeDefault, прежнее до-gVisor поведение); preflight пропускает проверку
RuntimeClass. Доступно супервизору без root.

## Правило evidence (существующая конвенция)

Копировать `evidence/<label>/` ДО `git worktree remove --force` —
summary.json живёт в worktree (урок verify-registry2).

## Правила переписывания истории (git filter-repo)

Урок 2026-10-13 (P2 публикации): карта `--replace-text` с пробелами вокруг `==>`
молча ничего не заменила — пробелы входят в литерал и замену (формат: `old==>new`,
без пробелов; префиксы `literal:`/`glob:`/`regex:` — по документации). Порядок:

1. **Проверить карту на тестовом клоне, а не на опубликованном репозитории:**
   `git clone` (или из bundle-бэкапа) в /tmp → filter-repo на копии →
   `git show HEAD:<файл>` и `git log --all -S <подстрока>` — только затем живой прогон.
2. Перед переписыванием: bundle-бэкап текущего main + внешняя копия всех
   gitignored-файлов, которые исчезнут из рабочего дерева (untracked-зона).
3. `--invert-paths` и `--replace-text` — один прогон; после него filter-repo
   удаляет remote'ы — re-add origin+github до push.
4. Force-push только по явному решению оператора; после него — проверка с нуля:
   fresh-клон `--recurse-submodules`, `git log --all -S <адрес>` = 0,
   `git log --all -- <пути>` = 0, guard-тест зелёный, mirror-репозиторий пересобран.
5. В публикуемые документы не вписывать внутренние адреса/хосты — они вернутся
   в историю новым коммитом.
