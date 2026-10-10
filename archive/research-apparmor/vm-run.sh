#!/bin/sh
# vm-run.sh (rev14, operator review #14): host-side orchestrator for the ONE-TIME
# VM that runs the X1a rev14 experiment. Reason (review #14): the W7 window
# temporarily sets kernel.yama.ptrace_scope=0 — a GLOBAL sysctl that weakens the
# whole host (same-UID processes could ptrace dumpable processes), and trap
# restore is not guaranteed after SIGKILL/hang/crash. So the experiment runs in a
# disposable VM with its own kernel; the VM is destroyed after verification.
#
# VM choice: Ubuntu 24.04 (noble) cloud image — kernel 6.8 + apparmor_parser 4.0.1,
# i.e. the same versions the mount-rule audit and the parser constraints were
# pinned to. The pinned Docker image (bubblewrap 0.8.0 inside — the audit basis)
# is transferred via docker save/load: content-addressed, the image ID is verified
# inside the VM before any container starts.
#
# Protocol: the operator stages vm-run.sh + x1a-test.sh + pinned.sha256 (2 lines:
#   line1 = x1a-test.sh sha256, line2 = vm-run.sh sha256) into /run/x1a-test
#   (root:root 0500/0400) and runs ONLY:  sudo /bin/sh /run/x1a-test/vm-run.sh
# vm-run.sh verifies its own hash (line2) and the test script's hash (line1)
# before doing anything, verifies every transferred input against the pins below,
# boots the VM, provisions it, runs the test script AS ROOT INSIDE THE VM,
# exports results to /tmp/x1a/vm-results-<ts>/, then destroys the VM (trap on
# every exit path: kill qemu + delete overlay/seed; the pinned base image stays).
#
# Host prerequisites (root apt, operator): qemu-system-x86 qemu-utils
# cloud-image-utils. /dev/kvm must be readable (the script runs as root).
set -u
umask 022

BASE=/run/x1a-test
SRC=/tmp/x1a
WORK=/var/tmp/x1a-vm
OUTBASE=/tmp/x1a

# ---------- pinned constants (2026-10-10; recompute on ANY change) ----------
EXP_SCRIPT_SHA=63f694755d67495a24af4c29bc14021795c1778c82f4ad277c128744a0115260
EXP_PROFILE_SHA=420505ed30ec7f6df094a27f217dc677574cc0d37cd8ee3287ae6f71c5b3f129
EXP_SECCOMP_SHA=480ebf2322a9151a08dc5b64a253ba25b7e2e0b94f0bc90b676285d41c0de997
EXP_W7_SHA=e22d0314143774166c71dfc0332defd5eda6c7085da46c492a741e1088a0baeb
EXP_WHARNESS_SHA=ee0e886dd8927ad24f711817eabaaaa535fb852c83708a52acfb1f4f00539ff5
EXP_PROBE_SHA=7164704e62938046571c257d30d91575d8dfce4d9e6f63bb1aff9dc38c343415
EXP_IMAGE_ID=sha256:913ad405b48948ab3c31d0222774163a65ad083b0c3541d8303be39380f5b15c
IMG_URL=https://cloud-images.ubuntu.com/noble/current/noble-server-cloudimg-amd64.img
IMG_SHA=6a81c37564db9b1ee84e141922625e1d7c5b389b99bb3c572e0243607d5bb4d2

VM_USER=ubuntu
SSH_PORT=2222
log(){ echo "[$(date -Is)] $*"; }
die(){ log "ABORT: $*"; exit 1; }

# ---------- 0. procedure guard ----------
[ "$(id -u)" = 0 ] || die "run as root (sudo /bin/sh $BASE/vm-run.sh): qemu needs /dev/kvm"
[ "$0" = "$BASE/vm-run.sh" ] || die "run only $BASE/vm-run.sh (the verified copy)"
[ -f "$0" ] && [ ! -L "$0" ] || die "$0 is not a regular file"
[ -d "$BASE" ] && [ ! -L "$BASE" ] || die "$BASE missing or not a plain dir"
PIN=$BASE/pinned.sha256
[ -f "$PIN" ] && [ ! -L "$PIN" ] || die "$PIN missing or not a regular file"
SELF_SHA=$(sha256sum "$0" | cut -d' ' -f1)
SCRIPT_SHA=$(sha256sum "$BASE/x1a-test.sh" 2>/dev/null | cut -d' ' -f1)
read -r PIN_SCRIPT < "$PIN"
PIN_VMRUN=$(sed -n '2p' "$PIN")
[ "$SELF_SHA" = "$PIN_VMRUN" ] || die "vm-run.sh hash mismatch: pinned=$PIN_VMRUN got=$SELF_SHA"
[ "$SCRIPT_SHA" = "$PIN_SCRIPT" ] && [ "$SCRIPT_SHA" = "$EXP_SCRIPT_SHA" ] \
  || die "x1a-test.sh hash mismatch: pinned=$PIN_SCRIPT exp=$EXP_SCRIPT_SHA got=$SCRIPT_SHA"
log "root copies verified: vm-run.sh=$SELF_SHA x1a-test.sh=$SCRIPT_SHA"

# ---------- 1. host prerequisites ----------
for t in qemu-system-x86_64 qemu-img cloud-localds ssh scp docker; do
  command -v "$t" >/dev/null || die "missing tool: $t (apt install qemu-system-x86 qemu-utils cloud-image-utils)"
done
[ -r /dev/kvm ] || die "/dev/kvm not readable"
sha(){ sha256sum "$1" | cut -d' ' -f1; }
check_input(){ # $1=path $2=expected
  [ -f "$1" ] && [ ! -L "$1" ] || die "input '$1' is not a regular file"
  h=$(sha "$1"); [ "$h" = "$2" ] || die "hash mismatch for '$1': expected $2 got $h"
  log "input OK: $1"
}
check_input "$SRC/rev13/stanok-x1a-test.apparmor" "$EXP_PROFILE_SHA"
check_input "$SRC/v-cli3.json"                     "$EXP_SECCOMP_SHA"
check_input "$SRC/rev13/w7-probe.py"               "$EXP_W7_SHA"
check_input "$SRC/rev13/w-harness.py"              "$EXP_WHARNESS_SHA"
check_input "$SRC/rev13/w-probe.py"                "$EXP_PROBE_SHA"
docker image inspect "$EXP_IMAGE_ID" >/dev/null 2>&1 || die "pinned image $EXP_IMAGE_ID not present"

# ---------- 2. work dir + pinned base image ----------
mkdir -p "$WORK" || die "cannot create $WORK"
IMG=$WORK/noble-server-cloudimg-amd64.img
if [ ! -f "$IMG" ]; then
  log "downloading pinned cloud image..."
  curl -sSL -o "$IMG.part" "$IMG_URL" || die "cloud image download failed"
  mv "$IMG.part" "$IMG"
fi
[ "$(sha "$IMG")" = "$IMG_SHA" ] || die "cloud image hash mismatch (expected $IMG_SHA)"
log "cloud image verified: $IMG_SHA"

# ---------- 3. VM lifecycle cleanup (trap on EVERY exit path) ----------
VM_PID=""
cleanup(){
  if [ -n "$VM_PID" ] && kill -0 "$VM_PID" 2>/dev/null; then
    log "destroying VM (pid $VM_PID)"; kill "$VM_PID" 2>/dev/null
    for i in 1 2 3 4 5 6 7 8 9 10; do kill -0 "$VM_PID" 2>/dev/null || break; sleep 1; done
    kill -9 "$VM_PID" 2>/dev/null
  fi
  rm -f "$WORK/vm-overlay.qcow2" "$WORK/seed.img" "$WORK/vm.pid" 2>/dev/null
  # the pinned base image and exported results are kept; the disposable parts are not
}
trap cleanup EXIT
trap 'cleanup; exit 130' INT
trap 'cleanup; exit 143' TERM

# ---------- 4. transfer artifacts ----------
log "docker save of the pinned image..."
docker save -o "$WORK/image.tar" "$EXP_IMAGE_ID" || die "docker save failed"
log "image.tar ready ($(wc -c < "$WORK/image.tar") bytes)"

# ssh key for the VM
[ -f "$WORK/vm_key" ] || ssh-keygen -t ed25519 -N "" -f "$WORK/vm_key" -q
PUB=$(cat "$WORK/vm_key.pub")

# cloud-init NoCloud seed
cat > "$WORK/user-data.yaml" <<EOF
#cloud-config
ssh_authorized_keys:
  - $PUB
package_update: true
packages:
  - docker.io
  - cloud-guest-utils
EOF
printf 'instance-id: x1a-vm\nlocal-hostname: x1a-vm\n' > "$WORK/meta-data.yaml"
cloud-localds "$WORK/seed.img" "$WORK/user-data.yaml" "$WORK/meta-data.yaml" || die "cloud-localds failed"

# overlay on the pinned base (base stays untouched); 12G virtual so the guest has
# room for docker.io + the loaded image; the guest FS is grown in preflight.
qemu-img create -f qcow2 -b "$IMG" -F qcow2 "$WORK/vm-overlay.qcow2" 12G >/dev/null || die "qemu-img create failed"

# ---------- 5. boot ----------
log "booting VM (qemu, KVM, 2 vCPU, 2048MB)..."
qemu-system-x86_64 -enable-kvm -m 2048 -smp 2 \
  -drive "file=$WORK/vm-overlay.qcow2,if=none,id=disk,format=qcow2" -device virtio-blk-pci,drive=disk \
  -drive "file=$WORK/seed.img,if=none,id=cidata,format=raw" -device virtio-blk-pci,drive=cidata \
  -netdev "user,id=n0,hostfwd=tcp:127.0.0.1:$SSH_PORT-:22" -device virtio-net-pci,netdev=n0 \
  -display none -serial "file:$WORK/serial.log" -daemonize -pidfile "$WORK/vm.pid" \
  || die "qemu boot failed (see $WORK/serial.log)"
VM_PID=$(cat "$WORK/vm.pid")
log "VM pid=$VM_PID"

SUDO_SSH="ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=$WORK/known_hosts -o ConnectTimeout=5 -i $WORK/vm_key -p $SSH_PORT"
SUDO_SCP="scp -o StrictHostKeyChecking=no -o UserKnownHostsFile=$WORK/known_hosts -i $WORK/vm_key -P $SSH_PORT"

# ---------- 6. wait for ssh ----------
log "waiting for ssh (cloud-init first boot)..."
UP=0
for i in $(seq 1 60); do
  if $SUDO_SSH "$VM_USER@127.0.0.1" true 2>/dev/null; then UP=1; break; fi
  sleep 5
done
[ "$UP" = 1 ] || { log "last serial lines:"; tail -20 "$WORK/serial.log" 2>/dev/null; die "ssh not up in 300s"; }
log "ssh up"

# ---------- 7. VM preflight (own kernel: AppArmor + Yama + docker) ----------
$SUDO_SSH "$VM_USER@127.0.0.1" '
  set -u
  uname -r
  test -e /sys/kernel/security/apparmor/profiles || { echo "NO-APPARMOR"; exit 1; }
  command -v apparmor_parser >/dev/null || { echo "NO-APPARMOR-PARSER"; exit 1; }
  apparmor_parser --version | head -1
  test -e /proc/sys/kernel/yama/ptrace_scope || { echo "NO-YAMA"; exit 1; }
  cat /proc/sys/kernel/yama/ptrace_scope
  for i in $(seq 1 30); do sudo docker info >/dev/null 2>&1 && break; sleep 5; done
  sudo docker info >/dev/null 2>&1 || { echo "NO-DOCKER"; exit 1; }
  sudo docker --version
  # grow the guest FS into the 12G overlay (base image is 3.5G virtual)
  sudo growpart /dev/vda 1 || true
  sudo resize2fs /dev/vda1 || true
  df -h / | tail -1
' || die "VM preflight failed"

# ---------- 8. transfer inputs + image; stage /run/x1a-test inside the VM ----------
log "transferring inputs + image to the VM..."
$SUDO_SSH "$VM_USER@127.0.0.1" 'mkdir -p /tmp/x1a/rev13 /tmp/vm-in' >/dev/null
$SUDO_SCP "$BASE/x1a-test.sh" "$VM_USER@127.0.0.1:/tmp/vm-in/x1a-test.sh"
$SUDO_SCP "$SRC/rev13/stanok-x1a-test.apparmor" "$SRC/rev13/w7-probe.py" "$SRC/rev13/w-harness.py" "$SRC/rev13/w-probe.py" \
          "$VM_USER@127.0.0.1:/tmp/x1a/rev13/"
$SUDO_SCP "$SRC/v-cli3.json" "$VM_USER@127.0.0.1:/tmp/x1a/"
$SUDO_SCP "$WORK/image.tar" "$VM_USER@127.0.0.1:/tmp/x1a/image.tar"
# verify hashes INSIDE the VM (transfer integrity), then stage the root copy
$SUDO_SSH "$VM_USER@127.0.0.1" "
  set -u
  cd /tmp/x1a
  [ \"\$(sha256sum rev13/stanok-x1a-test.apparmor | cut -d' ' -f1)\" = '$EXP_PROFILE_SHA' ] &&
  [ \"\$(sha256sum v-cli3.json | cut -d' ' -f1)\" = '$EXP_SECCOMP_SHA' ] &&
  [ \"\$(sha256sum rev13/w7-probe.py | cut -d' ' -f1)\" = '$EXP_W7_SHA' ] &&
  [ \"\$(sha256sum rev13/w-harness.py | cut -d' ' -f1)\" = '$EXP_WHARNESS_SHA' ] &&
  [ \"\$(sha256sum rev13/w-probe.py | cut -d' ' -f1)\" = '$EXP_PROBE_SHA' ] &&
  [ \"\$(sha256sum /tmp/vm-in/x1a-test.sh | cut -d' ' -f1)\" = '$EXP_SCRIPT_SHA' ] ||
  { echo 'VM INPUT HASH MISMATCH'; exit 1; }
  sudo mkdir -p /run/x1a-test
  sudo install -m 0500 -o root -g root /tmp/vm-in/x1a-test.sh /run/x1a-test/x1a-test.sh
  printf '%s\n%s\n' '$EXP_SCRIPT_SHA' '$SELF_SHA' | sudo tee /run/x1a-test/pinned.sha256 >/dev/null
  sudo chmod 0400 /run/x1a-test/pinned.sha256
  sudo docker load < /tmp/x1a/image.tar
  ID=\$(sudo docker image inspect '$EXP_IMAGE_ID' --format '{{.Id}}' 2>/dev/null)
  [ \"\$ID\" = '$EXP_IMAGE_ID' ] || { echo 'VM IMAGE ID MISMATCH'; exit 1; }
  echo VM-STAGED-OK
" || die "VM staging failed"
log "VM staged: inputs verified, image ID verified, /run/x1a-test prepared"

# ---------- 9. run the experiment INSIDE the VM (root; Yama window is VM-local) ----------
log "running x1a-test.sh inside the VM..."
$SUDO_SSH "$VM_USER@127.0.0.1" 'sudo /bin/sh /run/x1a-test/x1a-test.sh' > "$WORK/vm-run.log" 2>&1
RC=$?
cat "$WORK/vm-run.log"

# ---------- 10. export results ----------
TS=$(date -u +%Y%m%dT%H%M%SZ)
OUT=$OUTBASE/vm-results-$TS
mkdir -p "$OUT" || die "cannot create $OUT"
if ! $SUDO_SCP -r "$VM_USER@127.0.0.1:/run/x1a-test/results" "$OUT/results" 2>/dev/null; then
  $SUDO_SSH "$VM_USER@127.0.0.1" 'sudo tar czf /tmp/vm-results.tgz -C /run/x1a-test results' \
    && $SUDO_SCP "$VM_USER@127.0.0.1:/tmp/vm-results.tgz" "$OUT/results.tgz"
fi
cp "$WORK/vm-run.log" "$WORK/serial.log" "$OUT/" 2>/dev/null
chmod -R a+rX "$OUT" 2>/dev/null
log "results exported to $OUT"

# ---------- 11. verdict summary ----------
log "== VM RUN VERDICT: $([ "$RC" = 0 ] && echo PASS || echo FAIL) (rc=$RC)"
for m in "A7-strict PASS" "A7-weaker PASS" "W-MATRIX: PASS" "PROBE-SUMMARY: PASS" "W7-strict PASS" "W7-weaker PASS" "CLEANUP-OK" "== DONE"; do
  if grep -q "$m" "$WORK/vm-run.log"; then log "  marker OK: $m"; else log "  marker MISSING: $m"; fi
done
# destroy the VM (cleanup trap also covers failure paths)
if kill -0 "$VM_PID" 2>/dev/null; then
  $SUDO_SSH "$VM_USER@127.0.0.1" 'sudo poweroff' 2>/dev/null
  for i in 1 2 3 4 5 6 7 8 9 10; do kill -0 "$VM_PID" 2>/dev/null || break; sleep 1; done
  kill "$VM_PID" 2>/dev/null
  log "VM destroyed"
fi
exit "$RC"
