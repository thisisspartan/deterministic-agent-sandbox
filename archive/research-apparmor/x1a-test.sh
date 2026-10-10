#!/bin/sh
# X1a R4.2 one-time test (operator-confirmed protocol, 2026-10-09; rev8 after
# operator review #7). rev4: the root copy verifies its own SHA-256 against the
# external root-owned /run/x1a-test/pinned.sha256 before doing anything; the
# Docker image ID is pinned and verified before any container starts; all test
# container names must be free before the run; cleanup removes ONLY this run's
# containers (label stanok-x1a-run=<uuid>), never by blind name.
# rev7: all docker run commands use the pinned image ID directly (never the
# mutable tag); NO root writes into user-writable dirs — results stay in
# /run/x1a-test/results, read access is opened at the end, export is a separate
# non-root command by the operator.
# rev8: A8's outer process is a python3 harness (no px rule -> stays in the
# entry profile; its own profile print is the check), NOT /bin/sh (every shell
# has px -> sandbox and could not exec a mount-capable bwrap). Results access:
# $BASE gets traversal-only (a+x, NOT listable — the root script 0500, the pin
# and the staging dir 0700 stay unexposed); only $RES is opened for reading;
# done inside cleanup() so failure paths also expose results.
# rev9 (run1 FAIL: bwrap "Failed to make / slave" — kernel audit DENIED
# mount name="/" flags="rw, silent, rslave"): the profile gained the exact-match
# rule mount options=(rw, silent, rslave) -> / (new profile pin 128901bd…);
# the AppArmor kernel-log capture moved into cleanup() so it is saved on FAIL
# paths too. Launch note: /run is mounted noexec on this host — start with
#   sudo /bin/sh /run/x1a-test/x1a-test.sh   (direct exec gives EACCES).
# rev10 (run2 FAIL: bwrap "Failed to mount tmpfs" — kernel audit DENIED
# mount name="/tmp/" srcname="tmpfs" fstype=tmpfs, info="failed srcname match"):
# 'mount' rules without '->' treat the path as SOURCE, not mountpoint
# (apparmor.d(5) grammar). The four fstype rules were fixed to
# 'mount fstype=... -> <mountpoint>' (new profile pin 06fc2e51…);
# remount/umount take the mountpoint directly and were left unchanged.
# A static check below now rejects any 'mount'-keyword rule without '->'.
# rev11 (operator review #10): unspecified mount conditionals match ANY value
# (apparmor.d(5)), so the four fstype rules were tightened to exact
# fstype+srcname+options= forms matching bwrap 0.8.0's actual calls
# (bubblewrap.c :2554/:986 tmpfs MS_NOSUID|MS_NODEV, :991 devpts
# MS_NOSUID|MS_NOEXEC, :971 proc MS_NOSUID|MS_NOEXEC|MS_NODEV; same form as
# the published apparmor.d 'abstractions/bwrap'). No widening. New profile pin
# 6f284022c9416863a5a3743f670adddfd0ac48b97029bcb34dffef918c35441f.
# rev12 (operator review #11): full mount-rule audit against bubblewrap v0.8.0
# (bubblewrap.c, bind-mount.c) + kernel v6.8 security/apparmor/mount.c. Kernel
# encodes MS_BIND|MS_REC as 'rbind' (never 'bind'+'rbind'); aa_bind_mount()
# masks flags to MS_REC|MS_BIND -> every initial bind is mediated as 'rw, rbind'
# only; aa_mount_change_type() masks to MS_REC|MS_SILENT|MS_PRIVATE/SLAVE ->
# oldroot op is 'rw, silent, rprivate' (a mount rule, not remount); aa_remount()
# passes full flags -> remount rules carry no options=. Removed dead rules
# (remount /, remount /oldroot, options=(bind), options=(bind,rbind),
# options=(bind,ro)); added rprivate + 'umount /' (second pivot, main :2651) +
# rbind forms + 'remount /newroot/{,**}' ('**' alone does NOT match the
# directory itself). The static check below now also rejects a 'mount' rule
# without options= and a bare 'bind' flag token. New profile pin
# f6c9abef5ee8c6ceb23e7083879bc57503e2d76088fe8b8351d54dbb4d6b5b88.
# A8 harness extended with the entry-profile bypass test (direct clone() with
# the seccomp-pinned flag combination CLONE_NEWUSER|CLONE_NEWNS|CLONE_NEWPID|
# SIGCHLD=805437457 + mount inside the created namespace): the script now also
# requires 'CLONE-TEST: PASS'. New harness pin
# 8c270d8feccb87af3643d2101eadadd905dd21b27f2558724f598c7db70915fc.
# rev13 (operator reviews #12/#13): THREE-PROFILE model. The container gets
# stanok-worker-x1a-test (NO mount/umount/remount/pivot_root; the only path to
# mount rights is exec /usr/bin/bwrap px -> stanok-bwrap-x1a-test; bwrap's
# catch-all '/** px -> sandbox' strips mount rights from everything bwrap execs).
# review #13 closed the last inter-profile channel: ALL cross-profile ptrace
# rules removed (only within-profile ptrace remains). Test W7 (strict + weaker):
# from the sandbox, PTRACE_ATTACH to PID1 (the bwrap process), /proc/1/mem read
# and process_vm_readv must be DENIED, while PTRACE_ATTACH to the probe's own
# child (same profile, control C1) must PASS. Attribution (review #13 task 3):
# seccomp v-cli3.json ALLOWs ptrace/process_vm_readv unconditionally (verified
# 2026-10-10, lines 480-490); host Yama ptrace_scope is 1 and would deny a
# non-descendant ATTACH independently of AppArmor, so the script sets it to 0
# for the W7 window ONLY and restores it in cleanup(); tracer and target share
# uid 1000 (DAC allows). With C1 passing the only remaining gate is AppArmor;
# AppArmor audit records are captured as corroboration. A8/harness (worker-entry
# CLONE-TEST) is deferred to the harness-implementation round per review #13.
# rev14 (operator review #14): the three-profile model is PRELIMINARILY ACCEPTED
# for experimental verification; the full W1-W7 matrix is implemented (profiles
# byte-identical, pin 420505ed… unchanged). W-matrix (one container, worker entry,
# python3 harness w-harness.py -> stays worker: no px rule): W1 direct mount ->
# EACCES (AppArmor mediates before capabilities; EPERM would NOT prove AppArmor);
# W2 namespace-clone child inherits worker + mount EACCES despite caps in the new
# userns; W2b fork-child exec /usr/bin/bwrap -> mount-capable (strict setup OK);
# W3 copy of bwrap at /tmp/mybwrap execed from worker -> inherits worker -> setup
# FAILS; W6 bwrap execs python3 directly -> catch-all -> sandbox (own profile
# print). W4/W5 on the sandbox side via chained w-probe.py (P8, P10). Probe
# corrections vs the deferred a8-probe.py: P2/P4 expect EACCES(13) not EPERM(1)
# (AppArmor signature), P5/P6 gate on denial (seccomp ERRNO value is not the
# property under test). VERSION FACT (verified 2026-10-10): the pinned image's
# /usr/bin/bwrap is bubblewrap 0.8.0 — exactly the audit basis; the host's 0.9.0
# is irrelevant (the profile governs the CONTAINER's binary). RUNTIME: per review
# #14 this script runs inside a one-time VM (vm-run.sh) — the Yama ptrace_scope
# window must not weaken the main host; the VM kernel is disposable.
# The script's own SHA-256 is pinned OUTSIDE this file
# (specs/SPEC-X1A-MANAGED-PROFILES-2026-10-09.md R4.2); the operator verifies
# it, copies this file to /run/x1a-test/x1a-test.sh (root:root 0500) and runs
# ONLY that copy:  sudo /run/x1a-test/x1a-test.sh
#
# What is proven (separately, no mixing):
#   A7-strict : FULL chain in STRICT mode (enableWeakerNestedSandbox=false,
#               --proc): worker entry -> exec bwrap (px -> bwrap profile, its
#               mounts mediated there) -> exec /bin/sh (catch-all -> sandbox).
#   A7-weaker : same chain in WEAKER mode (current prod config: no --proc).
#   W-matrix  : W1 worker direct mount EACCES; W2 worker namespace-clone child
#               inherits worker, mount EACCES despite caps in the new userns;
#               W2b worker child exec /usr/bin/bwrap -> mount-capable;
#               W3 copied bwrap (/tmp/mybwrap) execed from worker -> inherits
#               worker -> setup FAILS; W4 nested bwrap from sandbox stays
#               confined (probe P8); W5 sandbox clone child inherits sandbox,
#               mount EACCES (probe P10); W6 bwrap execs python3 directly ->
#               catch-all -> sandbox profile.
#   W7-strict / W7-weaker : the untrusted sandbox command CANNOT interact with
#               the process that keeps the mount-capable bwrap profile (PID1 in
#               both modes): PTRACE_ATTACH, /proc/1/mem read and process_vm_readv
#               DENIED; ptrace of the probe's own child (same profile) allowed.
# Any FAIL -> stop, no automatic widening of permissions.
#
# Temporality of the test profiles: they are loaded into the kernel only, NOT
# installed into /etc/apparmor.d, and removed at the end (trap). `-K` only
# disables the apparmor_parser cache; it is not what makes the load temporary.
set -u
umask 022

BASE=/run/x1a-test
STAGE=$BASE/in
RES=$BASE/results

# ---------- 0. procedure guard: run only the verified root-owned staged copy ----------
BASE=/run/x1a-test
[ "$0" = "$BASE/x1a-test.sh" ] || { echo "ABORT: run only $BASE/x1a-test.sh (the verified copy)"; exit 1; }
[ -f "$0" ] && [ ! -L "$0" ] || { echo "ABORT: $0 is not a regular file"; exit 1; }
if [ -L "$BASE" ]; then echo "ABORT: $BASE is a symlink"; exit 1; fi
[ -d "$BASE" ] || { echo "ABORT: $BASE missing (created by the operator's copy step)"; exit 1; }
[ -d "$BASE" ] && [ ! -L "$BASE" ] || { echo "ABORT: $BASE failed re-check"; exit 1; }

# self-hash check against the EXTERNAL pinned value (root-owned file written by the
# operator before launch): the hash of the root copy must match the pin in the SPEC.
PIN=$BASE/pinned.sha256
[ -f "$PIN" ] && [ ! -L "$PIN" ] || { echo "ABORT: $PIN missing or not a regular file"; exit 1; }
read -r EXPECTED_SHA < "$PIN"
SELF_SHA=$(sha256sum "$0" | cut -d' ' -f1)
[ "$SELF_SHA" = "$EXPECTED_SHA" ] || {
  echo "ABORT: root copy hash mismatch"; echo "  pinned   $EXPECTED_SHA"; echo "  got      $SELF_SHA"; exit 1; }
echo "root copy hash verified: $SELF_SHA"

# fresh subdirs for inputs and results (root-owned 0700, outside any user-writable parent)
fresh_dir(){ # $1=path
  if [ -L "$1" ]; then echo "ABORT: $1 is a symlink"; return 1; fi
  if [ -e "$1" ]; then
    [ -d "$1" ] || { echo "ABORT: $1 exists and is not a directory"; return 1; }
    rm -rf -- "$1" || { echo "ABORT: cannot remove stale $1"; return 1; }
  fi
  mkdir -m 700 "$1" || { echo "ABORT: cannot create $1"; return 1; }
  [ -d "$1" ] && [ ! -L "$1" ] || { echo "ABORT: $1 failed re-check"; return 1; }
}
fresh_dir "$STAGE" || exit 1
fresh_dir "$RES"   || exit 1
log(){ echo "$@" | tee -a "$RES/run.log"; }

# ---------- 1. pinned inputs (2026-10-09). If any input changes: recompute and update. ----------
SRC=/tmp/x1a
EXP_PROFILE_SHA=420505ed30ec7f6df094a27f217dc677574cc0d37cd8ee3287ae6f71c5b3f129
EXP_SECCOMP_SHA=480ebf2322a9151a08dc5b64a253ba25b7e2e0b94f0bc90b676285d41c0de997
EXP_W7_SHA=e22d0314143774166c71dfc0332defd5eda6c7085da46c492a741e1088a0baeb
EXP_WHARNESS_SHA=ee0e886dd8927ad24f711817eabaaaa535fb852c83708a52acfb1f4f00539ff5
EXP_PROBE_SHA=7164704e62938046571c257d30d91575d8dfce4d9e6f63bb1aff9dc38c343415
# pinned image ID (docker image inspect, 2026-10-09): the test profile grants
# mount operations to the container — the exact image identity must be verified.
# After verification ALL docker run commands use this ID directly, never the
# mutable tag (the tag could be re-pointed between the check and the run).
EXP_IMAGE_ID=sha256:913ad405b48948ab3c31d0222774163a65ad083b0c3541d8303be39380f5b15c

ENTRY=stanok-worker-x1a-test
BWRAP=stanok-bwrap-x1a-test
SANDBOX=stanok-sandbox-x1a-test
IMAGE=stanok-machine:latest

log "== 0. preconditions $(date -Is)"
[ -d "$SRC" ] && [ ! -L "$SRC" ] || { log "ABORT: $SRC not a plain directory"; exit 1; }

# ---------- 2. input validation: regular files, pinned hashes ----------
sha(){ sha256sum "$1" | cut -d' ' -f1; }
check_input(){ # $1=path $2=expected-sha
  [ -f "$1" ] && [ ! -L "$1" ] || { log "ABORT: '$1' is not a regular file"; return 1; }
  h=$(sha "$1")
  if [ "$h" != "$2" ]; then
    log "ABORT: hash mismatch for '$1'"; log "  expected $2"; log "  got      $h"; return 1
  fi
  log "input OK: $1 sha256=$h"
}
check_input "$SRC/rev13/stanok-x1a-test.apparmor" "$EXP_PROFILE_SHA" || exit 1
check_input "$SRC/v-cli3.json"                     "$EXP_SECCOMP_SHA" || exit 1
check_input "$SRC/rev13/w7-probe.py"               "$EXP_W7_SHA"      || exit 1
check_input "$SRC/rev13/w-harness.py"              "$EXP_WHARNESS_SHA" || exit 1
check_input "$SRC/rev13/w-probe.py"                "$EXP_PROBE_SHA"    || exit 1

# ---------- 3. protected staging (root 0700; the ONLY paths used later) ----------
cp "$SRC/rev13/stanok-x1a-test.apparmor" "$STAGE/profile"
cp "$SRC/v-cli3.json"                     "$STAGE/v-cli3.json"
cp "$SRC/rev13/w7-probe.py"               "$STAGE/w7-probe.py"
cp "$SRC/rev13/w-harness.py"              "$STAGE/w-harness.py"
cp "$SRC/rev13/w-probe.py"                "$STAGE/w-probe.py"
chmod 400 "$STAGE/profile" "$STAGE/v-cli3.json"
chmod 444 "$STAGE/w7-probe.py" "$STAGE/w-harness.py" "$STAGE/w-probe.py"   # readable by the container's uid 1000
check_input "$STAGE/profile"      "$EXP_PROFILE_SHA" || exit 1
check_input "$STAGE/v-cli3.json"  "$EXP_SECCOMP_SHA" || exit 1
check_input "$STAGE/w7-probe.py"  "$EXP_W7_SHA"      || exit 1
check_input "$STAGE/w-harness.py" "$EXP_WHARNESS_SHA" || exit 1
check_input "$STAGE/w-probe.py"   "$EXP_PROBE_SHA"    || exit 1
log "staging verified: $STAGE (root:root 0700)"

# ---------- 4. kernel preconditions ----------
for n in "$ENTRY" "$BWRAP" "$SANDBOX"; do
  if grep -qw "$n" /sys/kernel/security/apparmor/profiles 2>/dev/null; then
    log "ABORT: test profile '$n' already loaded in kernel"; exit 1
  fi
done
if grep -rl "x1a-test" /etc/apparmor.d/ >/dev/null 2>&1; then
  log "ABORT: test profile names referenced in /etc/apparmor.d"; exit 1
fi
if ! docker image inspect "$IMAGE" >/dev/null 2>&1; then
  log "ABORT: image $IMAGE not present"; exit 1
fi
IMAGE_ID=$(docker image inspect "$IMAGE" --format '{{.Id}}' 2>/dev/null)
if [ "$IMAGE_ID" != "$EXP_IMAGE_ID" ]; then
  log "ABORT: image ID mismatch (the test profile grants mount ops to this container)"
  log "  expected $EXP_IMAGE_ID"
  log "  got      $IMAGE_ID"
  exit 1
fi
log "image ID verified: $IMAGE_ID"
# test container names must be free: cleanup only removes this run's labeled containers
for n in stanok-x1a-a7-strict stanok-x1a-a7-weaker stanok-x1a-wmatrix stanok-x1a-w7-strict stanok-x1a-w7-weaker; do
  if docker ps -a --format '{{.Names}}' 2>/dev/null | grep -qx "$n"; then
    log "ABORT: container name '$n' already in use"; exit 1
  fi
done
RUNID=$(cat /proc/sys/kernel/random/uuid)
log "run id: $RUNID (containers labeled stanok-x1a-run=$RUNID)"
log "kernel preconditions OK"

# parse-check without loading into kernel
if ! apparmor_parser -Q -K "$STAGE/profile" >"$RES/parse.out" 2>"$RES/parse.err"; then
  log "ABORT: profile parse failed"; cat "$RES/parse.err" | tee -a "$RES/run.log"; exit 1
fi
log "parse-check OK (apparmor_parser -Q -K)"

# static mount-rule semantics check (rev10 + rev12, operator reviews #9/#11):
# (a) for the 'mount' keyword a path WITHOUT '->' is the SOURCE device, not the
#     mountpoint (apparmor.d(5); run2 audit: info="failed srcname match"
#     name="/tmp/" srcname="tmpfs"). Every 'mount'-keyword rule must use
#     '-> <mountpoint>'. 'remount'/'umount' take the mountpoint directly
#     (grammar REMOUNT/UMOUNT = ... MOUNTPOINT FILEGLOB) and are exempt;
#     comments and 'pivot_root'/'remount'/'umount' lines never match the pattern.
# (b) unspecified mount conditionals match ANY value (apparmor.d(5)) — every
#     'mount' rule must pin options= (operator review #10).
# (c) bare 'bind' token: the kernel encodes MS_BIND|MS_REC as 'rbind' and
#     aa_bind_mount() masks flags to MS_REC|MS_BIND (v6.8 security/apparmor/
#     mount.c); all bwrap binds are recursive (bubblewrap.c:964) — a rule with
#     a bare 'bind' token can never match any request (dead rule, rev11 defect).
if awk '/^[[:space:]]*mount[[:space:]]/ {
       if ($0 !~ /->/) { print "BAD (no ->, path would be SOURCE): " $0; bad=1 }
       if (!match($0, /options=\([^)]*\)/)) { print "BAD (no options= — conditionals would match ANY flags): " $0; bad=1; next }
       opts = substr($0, RSTART + 9, RLENGTH - 10)
       n = split(opts, toks, "[, ]")
       for (i = 1; i <= n; i++)
         if (toks[i] == "bind") { print "BAD (bare bind token — kernel audits recursive binds as rbind): " $0; bad=1 }
     } END { exit (bad ? 1 : 0) }' \
     "$STAGE/profile" >"$RES/mount-rules-check.txt" 2>&1; then
  log "mount-rule semantics check OK (every 'mount' rule: '-> mountpoint', pinned options=, no bare 'bind' token; remount/umount exempt per grammar)"
else
  log "ABORT: 'mount' rule defects found in the profile (no '->' / no options= / bare 'bind')"
  cat "$RES/mount-rules-check.txt" | tee -a "$RES/run.log"
  exit 1
fi

# ---------- 5. cleanup trap BEFORE the first load attempt ----------
LOADED=0; CLEANED=0; CLEAN_RC=0; YAMA_CHANGED=0; YAMA_OLD=1
cleanup(){
  if [ "$CLEANED" = 1 ]; then return "$CLEAN_RC"; fi
  CLEANED=1
  if [ "$LOADED" = 1 ]; then
    apparmor_parser -R -K "$STAGE/profile" >"$RES/unload.out" 2>&1 \
      || log "cleanup: apparmor_parser -R reported an error (see unload.out)"
  fi
  # remove ONLY containers created by this run (label), never by blind name
  ids=$(docker ps -aq --filter "label=stanok-x1a-run=$RUNID" 2>/dev/null)
  if [ -n "$ids" ]; then
    docker rm -f $ids >/dev/null 2>&1 || log "cleanup: docker rm reported an error"
  fi
  CLEAN_RC=0
  if [ "$YAMA_CHANGED" = 1 ]; then
    echo "$YAMA_OLD" > /proc/sys/kernel/yama/ptrace_scope 2>/dev/null \
      || log "cleanup: Yama ptrace_scope restore FAILED (manual restore needed: $YAMA_OLD)"
  fi
  for n in "$ENTRY" "$BWRAP" "$SANDBOX"; do
    if grep -qw "$n" /sys/kernel/security/apparmor/profiles 2>/dev/null; then
      log "CLEANUP-FAIL: '$n' still loaded in kernel policy"; CLEAN_RC=1
    else
      log "CLEANUP-OK: '$n' absent from kernel policy"
    fi
  done
  # save AppArmor kernel-log diagnostics (runs on ALL paths, incl. FAIL)
  dmesg 2>/dev/null | grep -i apparmor > "$RES/dmesg-apparmor.txt" 2>&1 || true
  # controlled read access to results (also on failure paths): $BASE gets
  # traversal-ONLY (a+x, NOT listable — the root script 0500, the pin and the
  # staging dir 0700 stay unexposed); only $RES is opened for reading.
  chmod a+x "$BASE" 2>/dev/null || log "cleanup: chmod $BASE failed"
  chmod -R a+rX "$RES" 2>/dev/null || log "cleanup: chmod $RES failed"
  return "$CLEAN_RC"
}
trap 'cleanup; exit 130' INT
trap 'cleanup; exit 143' TERM
trap 'cleanup || exit 1' EXIT

# ---------- 6. load: ADD (-a), NOT replace (-r); LOADED=1 before the attempt ----------
LOADED=1
if ! apparmor_parser -a -K "$STAGE/profile" >"$RES/load.out" 2>&1; then
  log "ABORT: apparmor_parser -a failed"; cat "$RES/load.out" | tee -a "$RES/run.log"; exit 1
fi
for n in "$ENTRY" "$BWRAP" "$SANDBOX"; do
  if ! grep -qw "$n" /sys/kernel/security/apparmor/profiles; then
    log "ABORT: '$n' not visible in kernel profiles after load"; exit 1
  fi
done
log "profiles loaded and visible in /sys/kernel/security/apparmor/profiles"

# ---------- 7. A7-strict: STRICT mode (enableWeakerNestedSandbox=false, --proc /proc) ----------
log "== A7-strict $(date -Is)"
docker run --rm --name stanok-x1a-a7-strict --label "stanok-x1a-run=$RUNID" --network=none \
  --cap-drop=ALL --security-opt=no-new-privileges \
  --security-opt "seccomp=$STAGE/v-cli3.json" --security-opt "apparmor=$ENTRY" \
  --user 1000:1000 "$EXP_IMAGE_ID" \
  bwrap --ro-bind / / --dev /dev --proc /proc --new-session --die-with-parent \
        --unshare-user --unshare-pid --unshare-net \
        -- /bin/sh -c 'echo A7-OK; cat /proc/self/attr/current' \
  >"$RES/a7-strict.out" 2>&1
A7RC=$?
log "A7-strict rc=$A7RC"; cat "$RES/a7-strict.out" | tee -a "$RES/run.log"
if [ "$A7RC" -ne 0 ] || ! grep -q "A7-OK" "$RES/a7-strict.out" || ! grep -q "$SANDBOX" "$RES/a7-strict.out"; then
  log "A7-strict FAIL — STOP (no widening)"; exit 1
fi
log "A7-strict PASS: strict mode works; inner /bin/sh is in profile '$SANDBOX'"

# ---------- 8. A7-weaker: WEAKER mode (current prod config, no --proc) — separate test ----------
log "== A7-weaker $(date -Is)"
docker run --rm --name stanok-x1a-a7-weaker --label "stanok-x1a-run=$RUNID" --network=none \
  --cap-drop=ALL --security-opt=no-new-privileges \
  --security-opt "seccomp=$STAGE/v-cli3.json" --security-opt "apparmor=$ENTRY" \
  --user 1000:1000 "$EXP_IMAGE_ID" \
  bwrap --ro-bind / / --dev /dev --new-session --die-with-parent \
        --unshare-user --unshare-pid --unshare-net \
        -- /bin/sh -c 'echo A7-OK; cat /proc/self/attr/current' \
  >"$RES/a7-weaker.out" 2>&1
A7WRC=$?
log "A7-weaker rc=$A7WRC"; cat "$RES/a7-weaker.out" | tee -a "$RES/run.log"
if [ "$A7WRC" -ne 0 ] || ! grep -q "A7-OK" "$RES/a7-weaker.out" || ! grep -q "$SANDBOX" "$RES/a7-weaker.out"; then
  log "A7-weaker FAIL — STOP (no widening)"; exit 1
fi
log "A7-weaker PASS: weaker mode works; inner /bin/sh is in profile '$SANDBOX'"

# ---------- 9. W-matrix (W1-W6): the mount-rights claim of the three-profile model.
#   One container, worker entry: python3 has NO px rule -> the harness stays in
#   the worker profile (its H-P print verifies this). W1-W3/W2b/W6 from the
#   worker side; W4/W5 via the chained sandbox-side probe (P8/P10). ----------
log "== W-matrix W1-W6 $(date -Is)"
docker run --rm --name stanok-x1a-wmatrix --label "stanok-x1a-run=$RUNID" --network=none \
  -v "$STAGE/w-harness.py:/w-harness.py:ro" -v "$STAGE/w-probe.py:/w-probe.py:ro" \
  --cap-drop=ALL --security-opt=no-new-privileges \
  --security-opt "seccomp=$STAGE/v-cli3.json" --security-opt "apparmor=$ENTRY" \
  --user 1000:1000 "$EXP_IMAGE_ID" \
  /usr/bin/python3 /w-harness.py \
  >"$RES/w-matrix.out" 2>&1
WMRC=$?
log "W-matrix rc=$WMRC"; cat "$RES/w-matrix.out" | tee -a "$RES/run.log"
if [ "$WMRC" -ne 0 ] || ! grep -q "W-MATRIX: PASS" "$RES/w-matrix.out" \
   || ! grep -q "PROBE-SUMMARY: PASS" "$RES/w-matrix.out"; then
  log "W-matrix FAIL — STOP (no widening)"; exit 1
fi
log "W-matrix PASS: mount rights exist only in the bwrap profile (W1-W6)"
# corroboration (not a gate): AppArmor DENIED mount records naming the worker and
# sandbox profiles (W1/W2/W3/W4/W5 denials must be attributed to AppArmor).
dmesg 2>/dev/null | grep -i apparmor | grep -i "DENIED" > "$RES/w-matrix-audit.txt" 2>&1 || true
log "W-matrix audit corroboration captured ($(grep -c . "$RES/w-matrix-audit.txt" 2>/dev/null || echo 0) DENIED records in w-matrix-audit.txt)"

# ---------- 10. W7-strict / W7-weaker: the ptrace channel sandbox -> bwrap is CLOSED.
#              Target PID1 is the bwrap process in BOTH modes: strict -> fresh
#              procfs/pidns, bwrap is PID1 there; weaker -> the container's PID1
#              IS bwrap (docker runs bwrap as the container command). ----------
# Attribution window (review #13 task 3): host Yama ptrace_scope=1 would deny a
# non-descendant PTRACE_ATTACH independently of AppArmor -> set it to 0 for the
# W7 window only; cleanup() restores it. seccomp ALLOWs ptrace/process_vm_readv
# (pinned v-cli3.json, verified); same uid 1000 -> DAC allows. Control C1 inside
# the probe (attach to its own child, same profile) must PASS.
YAMA_FILE=/proc/sys/kernel/yama/ptrace_scope
if [ -f "$YAMA_FILE" ]; then
  YAMA_OLD=$(cat "$YAMA_FILE")
  if [ "$YAMA_OLD" != "0" ]; then
    echo 0 > "$YAMA_FILE" || { log "ABORT: cannot set Yama ptrace_scope=0 for the W7 window"; exit 1; }
    YAMA_CHANGED=1
    log "Yama ptrace_scope: $YAMA_OLD -> 0 (W7 window only; restored in cleanup)"
  fi
fi

log "== W7-strict $(date -Is)"
docker run --rm --name stanok-x1a-w7-strict --label "stanok-x1a-run=$RUNID" --network=none \
  -v "$STAGE/w7-probe.py:/w7.py:ro" \
  --cap-drop=ALL --security-opt=no-new-privileges \
  --security-opt "seccomp=$STAGE/v-cli3.json" --security-opt "apparmor=$ENTRY" \
  --user 1000:1000 "$EXP_IMAGE_ID" \
  bwrap --ro-bind / / --dev /dev --proc /proc --new-session --die-with-parent \
        --unshare-user --unshare-pid --unshare-net \
        -- /usr/bin/python3 /w7.py \
  >"$RES/w7-strict.out" 2>&1
W7RC=$?
log "W7-strict rc=$W7RC"; cat "$RES/w7-strict.out" | tee -a "$RES/run.log"
if [ "$W7RC" -ne 0 ] || ! grep -q "W7-SUMMARY: PASS" "$RES/w7-strict.out" \
   || ! grep -q "PASS C1-ptrace-own-child-allowed" "$RES/w7-strict.out"; then
  log "W7-strict FAIL — STOP (no widening)"; exit 1
fi
log "W7-strict PASS: sandbox cannot ptrace/read/process_vm_readv the bwrap process"

log "== W7-weaker $(date -Is)"
docker run --rm --name stanok-x1a-w7-weaker --label "stanok-x1a-run=$RUNID" --network=none \
  -v "$STAGE/w7-probe.py:/w7.py:ro" \
  --cap-drop=ALL --security-opt=no-new-privileges \
  --security-opt "seccomp=$STAGE/v-cli3.json" --security-opt "apparmor=$ENTRY" \
  --user 1000:1000 "$EXP_IMAGE_ID" \
  bwrap --ro-bind / / --dev /dev --new-session --die-with-parent \
        --unshare-user --unshare-pid --unshare-net \
        -- /usr/bin/python3 /w7.py \
  >"$RES/w7-weaker.out" 2>&1
W7WRC=$?
log "W7-weaker rc=$W7WRC"; cat "$RES/w7-weaker.out" | tee -a "$RES/run.log"
if [ "$W7WRC" -ne 0 ] || ! grep -q "W7-SUMMARY: PASS" "$RES/w7-weaker.out" \
   || ! grep -q "PASS C1-ptrace-own-child-allowed" "$RES/w7-weaker.out"; then
  log "W7-weaker FAIL — STOP (no widening)"; exit 1
fi
log "W7-weaker PASS: sandbox cannot ptrace/read/process_vm_readv the bwrap process"

# corroboration (not a gate): AppArmor audit records for the W7 denials.
dmesg 2>/dev/null | grep -i apparmor | grep -i "ptrace" > "$RES/w7-audit.txt" 2>&1 || true
if grep -qi 'DENIED' "$RES/w7-audit.txt"; then
  log "W7 audit corroboration: AppArmor ptrace DENIED records captured ($(grep -c . "$RES/w7-audit.txt") lines in w7-audit.txt)"
else
  log "W7 audit corroboration: no AppArmor ptrace DENIED record in dmesg (attribution rests on Yama=0 + C1 + seccomp ALLOW)"
fi

# ---------- 11. explicit cleanup (trap is the safety net; kernel-log capture is in cleanup()) ----------
cleanup
RC=$?
if [ "$RC" -ne 0 ]; then log "EXPERIMENT FAILED: cleanup did not remove the test profiles"; exit 1; fi
log "== DONE $(date -Is); results in $RES"

# ---------- 12. results access (opened by cleanup(): $BASE traversal-only, $RES readable) ----------
# This root script never writes into a user-writable directory (a user could swap
# the PUB subdir between mkdir and cp — TOCTOU). cleanup() gave $BASE traversal-only
# (a+x, NOT listable: the root script 0500, the pin and the staging dir 0700 stay
# unexposed) and opened $RES for reading. The export to a user directory is a
# SEPARATE command run WITHOUT root by the operator afterwards, e.g.:
#   cp -a /run/x1a-test/results /tmp/x1a/results-$(date -u +%Y%m%dT%H%M%SZ)
log "results reachable+readable at $RES ($BASE traversal-only; export: separate non-root command)"
