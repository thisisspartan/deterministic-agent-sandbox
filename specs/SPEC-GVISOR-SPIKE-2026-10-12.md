# SPEC-GVISOR-SPIKE-2026-10-12 — gVisor spike (план усиления, задача 3)

Заказ оператора (2026-10-12): runsc + RuntimeClass в k3s; **критерий утилитарный**:
совместимость фактической нагрузки (Claude Code CLI / Bash / pytest / PTY) + оверхед.
Отказ → фиксация RuntimeDefault как принятого риска в RA-5 (спайк закрыт, ничего не
внедряется). Задачи host-side (k8s/, launcher/ — вне зон машины), machine-тикет только
на Phase 3 и только при прохождении Phase 1+2.

## Проверенные факты (2026-10-12)

- k3s v1.36.5+k3s1, containerd 2.3.4-k3s1.36 → конфиг version 3; кастомизация —
  шаблон `/var/lib/rancher/k3s/agent/etc/containerd/config-v3.toml.tmpl`
  (расширение базы `{{ template "base" . }}`, docs.k3s.io/advanced).
- k3s auto-detect альтернативных runtime: crun/lunatic/nvidia/slight/spin/wasmedge/
  wasmer/wasmtime/wws — **runsc НЕ в списке** (в кластере уже есть RuntimeClass'ы
  этих runtime; gvisor надо создавать вручную) → обязателен явный containerd-шаблон
  + ручной RuntimeClass.
- runsc не установлен; у супервизора нет passwordless sudo → **Phase 0 — root,
  только оператор**.
- Worker-Pod securityContext (mirror для smoke-Pod): runAsUser 10001 non-root,
  readOnlyRootFilesystem, drop ALL caps, seccomp RuntimeDefault, emptyDir /tmp +
  work; сеть — NetworkPolicy `stanok: worker` (egress только model/Opik :8080,
  DNS-блэкаут → IP-литералы). Image: `stanok-machine:latest`,
  imagePullPolicy IfNotPresent (дефолт Always для `:latest` → ImagePullBackOff —
  инцидент probe-Pod 2026-10-12).
- Claude CLI в образе: `/usr/local/bin/claude` → `/opt/claude-code-2.1.88/cli.js`;
  в образе есть node, python3, pytest, bash (стек реальных прогонов).
- Baseline elapsed_s реальных прогонов (RuntimeDefault, CLEAN-FIRST, 1 turn):
  cc240 377s, cc241 225s, cc242 574s, cc243 372s, cc244 346s (медиана ~360s).

## Критерии (утилитарные, измеримые)

- **P1 (совместимость):** probe-Pod под `runtimeClassName: gvisor` даёт тот же
  результат, что control-Pod (RuntimeDefault): `claude --version`, `node --version`,
  `python3 -m pytest --version`, bash-скрипт, mkdir-паттерн Bash-инструмента CLI
  (`/tmp/claude-<uid>/…`), запись в work-volume, ro-rootfs отказ, egress к
  model-server (`GET http://192.168.8.131:8080/props`), PTY (stdlib
  `os.forkpty` + spawn `/bin/bash -c 'echo PTY-OK'`).
- **P2 (оверхед Pod):** по timestamp'ам Pod status (startedAt−creationTimestamp =
  startup; finishedAt−startedAt = исполнение): startup-оверхед ≤ 2s (gVisor
  документирован ~200ms; больше = не утилитарно), время probe ≤ control + 20%;
  3 прогона на каждый runtime, медиана.
- **P3 (реальный прогон, только при P1+P2):** обычный machine-тикет (CC-245,
  маленький py-тикет: src+tests+docs — полный путь TDD/pytest/run.sh/fresh-check)
  через `launch.sh` с `STANOK_K8S_RUNTIME_CLASS=gvisor`: вердикт CLEAN-FIRST,
  elapsed_s ≤ baseline-медиана + 20% (~430s).
- PASS = P1 ∧ P2 ∧ P3. Любой FAIL → ветка «Отказ» (ниже).

## Phase 0 — root (оператор)

```bash
cd /tmp
curl -fsSLO https://storage.googleapis.com/gvisor/releases/release/latest/x86_64/runsc
curl -fsSLO https://storage.googleapis.com/gvisor/releases/release/latest/x86_64/containerd-shim-runsc-v1
sudo install -m 0755 runsc containerd-shim-runsc-v1 /usr/local/bin/
runsc --version
# какой шаблон нужен — по факту сгенерированного конфига:
ls /var/lib/rancher/k3s/agent/etc/containerd/   # есть config-v3.toml → config-v3.toml.tmpl
sudo tee /var/lib/rancher/k3s/agent/etc/containerd/config-v3.toml.tmpl >/dev/null <<'EOF'
{{ template "base" . }}

[plugins.'io.containerd.cri.v1.runtime'.containerd.runtimes.'runsc']
  runtime_type = "io.containerd.runsc.v1"
EOF
sudo systemctl restart k3s
```

Проверка оператором после рестарта: `kubectl get nodes` — Ready;
`grep -A2 runsc /var/lib/rancher/k3s/agent/etc/containerd/config.toml` — запись есть.
(Если k3s сгенерировал legacy `config.toml` version 2 — использовать
`config.toml.tmpl` с `[plugins."io.containerd.grpc.v1.cri".containerd.runtimes.runsc]`.)

## Phase 1 — supervisor: RuntimeClass + probe-Pod (control vs gvisor)

1. RuntimeClass:
```yaml
apiVersion: node.k8s.io/v1
kind: RuntimeClass
metadata: {name: gvisor}
handler: runsc
```
2. probe-скрипт → ConfigMap `gvisor-probe` (`--from-file`), probe-Pod
   `gvisor-probe-{control|gvisor}` в ns default: зеркало worker securityContext +
   label `stanok: worker` (реальный netpol), image stanok-machine:latest
   IfNotPresent, command `["/bin/bash","/probe/probe.sh"]`, runtimeClassName
   только в gvisor-варианте.
3. probe.sh (одинаковый вывод обоих runtime = P1):
```bash
#!/bin/bash
set -e
echo "PROBE uid=$(id -u) host=$(hostname)"
claude --version
node --version
python3 --version
python3 -m pytest --version
mkdir -p "/tmp/claude-$(id -u)/probe" && echo ok > "/tmp/claude-$(id -u)/probe/x" && cat "/tmp/claude-$(id -u)/probe/x"
echo ok > /stanok-work/probe.txt && cat /stanok-work/probe.txt
if touch /ro-rootfs-test 2>/dev/null; then echo "RO-ROOTFS BROKEN"; else echo "RO-ROOTFS ok"; fi
python3 -c 'import urllib.request as u; r=u.urlopen("http://192.168.8.131:8080/props",timeout=10); print("NET ok",r.status,len(r.read()))'
python3 - <<'PY'
import os, select
pid, m = os.forkpty()
if pid == 0:
    os.execvp("/bin/bash", ["/bin/bash", "-c", "echo PTY-OK"])
out = b""
while True:
    r,_,_ = select.select([m],[],[],10)
    if not r: break
    try: out += os.read(m, 1024)
    except OSError: break
os.waitpid(pid, 0)
assert b"PTY-OK" in out, out
print("PTY ok")
PY
echo "PROBE DONE"
```

## Phase 2 — supervisor: оверхед

3 прогона на каждый runtime; метрики из `kubectl get pod -o json`
(creationTimestamp, containerStatuses[0].state.terminated.startedAt/finishedAt);
медианы сравниваются (P2). Все probe-Pod/ConfigMap удаляются после фазы.

## Phase 3 — supervisor: реальный прогон (только при P1+P2)

Host-side правка харнесса: knob `STANOK_K8S_RUNTIME_CLASS` (env; unset =
RuntimeDefault — поведение не меняется; `gvisor` → `runtimeClassName: gvisor` в
worker-job.yaml.tmpl и fresh-job.yaml.tmpl) + пин в test_k8s_manifests.py
рендер обеих веток. Затем обычный тикет CC-245 через `launch.sh run … --follow`
с этим env; приёмка по обычным правилам (SUCCESS = rc=0, verifier PASS,
probe≠CONTRACT-FAIL).

## Решение

- PASS → gvisor принимается как runtime worker/fresh Jobs (knob включён по
  умолчанию оператором — решение оператора); запись в STATUS/CONTEXT.
- FAIL (любая фаза) → RA-5 addendum в specs/RISK-ACCEPTANCES.md: «RuntimeDefault
  (runc) — принятый runtime; gVisor отвергнут спайком <дата>», evidence/ прогона
  как доказательство; RuntimeClass и probe-ресурсы удалены.

## Границы

- Мораторий не затронут (Tetragon/ACS/Breaker/AST/snapshots/SLSA/mutation — вне).
- Phase 0 — единственные root-действия; супервизор их не выполняет (нет sudo).
- Machine-зон (src/tests/docs) спайк не касается; единственный machine-тикет —
  CC-245 на Phase 3 при PASS.
