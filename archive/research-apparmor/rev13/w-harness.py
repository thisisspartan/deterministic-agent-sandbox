# W-harness (rev14, operator review #14): runs as the container's PID1 under the
# WORKER profile (docker assigns it; python3 has NO px rule -> the harness stays
# in the worker profile; its own profile print H-P is the verification, not an
# assumption). Proves the mount-rights claim of the three-profile model from the
# worker side:
#   W1  direct mount() from the worker profile            -> EACCES. AppArmor
#       mediates sb_mount BEFORE the capability check, so EACCES is the AppArmor
#       signature; EPERM would mean a capability denial, not AppArmor.
#   W2  clone(CLONE_NEWUSER|CLONE_NEWNS|CLONE_NEWPID|SIGCHLD = 805437457) —
#       exactly the flag combination allowed by the pinned seccomp (v-cli3.json).
#       The child owns a new userns (the creator's uid is auto-mapped to 0 ->
#       full caps over the new mountns) + new mountns + new pidns and INHERITS
#       the worker profile (profile is inherited across clone; only exec changes
#       it). Caps are present, so a DENY here is AppArmor: mount -> EACCES.
#   W2b plain fork()+exec of /usr/bin/bwrap from the worker profile: the exact
#       px rule -> bwrap profile -> the full strict bwrap setup SUCCEEDS. This
#       is the ONLY path to mount rights (A7 proves the same chain as the
#       container command; here it is proven from a worker-profile child).
#   W3  copy of /usr/bin/bwrap at /tmp/mybwrap execed from the worker profile:
#       no px rule for that path -> inherits the worker profile -> the bwrap
#       setup FAILS (its mount operations are denied). rc != 0 is the gate;
#       the script captures the AppArmor audit naming the worker profile as
#       corroboration.
#   W6  bwrap execs python3 DIRECTLY (no shell in between): the bwrap profile's
#       catch-all '/** px -> sandbox' applies to ANY command -> python3 lands in
#       the sandbox profile (print of its own attr/current is the check).
# W4/W5 are proven on the sandbox side by the chained probe (w-probe.py P8/P10).
import ctypes, mmap, os, shutil, subprocess, sys

libc = ctypes.CDLL("libc.so.6", use_errno=True)
MS_NOSUID, MS_NODEV = 2, 4
CLONE_FLAGS = 805437457  # CLONE_NEWUSER|CLONE_NEWNS|CLONE_NEWPID|SIGCHLD (pinned seccomp)
WORKER = "stanok-worker-x1a-test"
SANDBOX = "stanok-sandbox-x1a-test"
results = []

def check(name, cond, detail):
    results.append(cond)
    print(("PASS " if cond else "FAIL ") + name + " :: " + detail, flush=True)

def errno_name():
    e = ctypes.get_errno()
    return {1: "EPERM", 13: "EACCES", 2: "ENOENT"}.get(e, str(e))

def try_mount(target):
    r = libc.mount(b"tmpfs", target.encode(), b"tmpfs",
                   ctypes.c_ulong(MS_NOSUID | MS_NODEV), None)
    if r == 0:
        return "OK"
    return errno_name()

# STRICT-mode bwrap args (same chain as A7-strict; the mount operations are the
# audited set — weaker mode differs only in the /proc bind, A7-weaker covers it).
BWRAP_ARGS = ["--ro-bind", "/", "/", "--dev", "/dev", "--proc", "/proc",
              "--new-session", "--die-with-parent",
              "--unshare-user", "--unshare-pid", "--unshare-net"]

# H-P: own profile must be the worker profile (the whole matrix is meaningless otherwise)
prof = open("/proc/self/attr/current").read().strip()
check("H-P-own-profile-worker", prof == WORKER, prof)

# --- W1: direct mount from the worker profile -> EACCES (AppArmor, not caps) ---
try:
    os.mkdir("/tmp/escape-w1")
except FileExistsError:
    pass
w1 = try_mount("/tmp/escape-w1")
check("W1-worker-mount-denied-EACCES", w1 == "EACCES", w1)

# --- W2: namespace-clone child inherits the worker profile; caps exist in the
#     new userns; mount is STILL denied by AppArmor (EACCES). ---
r_fd, w_fd = os.pipe()

def child_fn(_arg):
    p = open("/proc/self/attr/current").read().strip()
    try:
        os.mkdir("/tmp/escape-w2")
    except FileExistsError:
        pass
    m = try_mount("/tmp/escape-w2")
    os.write(w_fd, (p + "|" + m).encode())
    os._exit(0)
    return 0

STACK = 1 << 20
mm = mmap.mmap(-1, STACK)
top = ctypes.addressof(ctypes.c_char.from_buffer(mm)) + STACK
cb = ctypes.CFUNCTYPE(ctypes.c_int, ctypes.c_void_p)(child_fn)
libc.clone.restype = ctypes.c_int
pid = libc.clone(cb, ctypes.c_void_p(top), ctypes.c_int(CLONE_FLAGS), ctypes.c_void_p(0))
if pid < 0:
    check("W2-clone-child-confined", False, "clone() blocked: " + errno_name())
else:
    os.waitpid(pid, 0)
    got = os.read(r_fd, 256).decode(errors="replace")
    cp, cm = (got.split("|") + ["", ""])[:2]
    check("W2-clone-child-confined", cp == WORKER and cm == "EACCES",
          "child profile=%s mount=%s (caps present in new userns)" % (cp, cm))

# --- W2b: exec /usr/bin/bwrap from the worker profile -> bwrap profile ->
#     full strict setup SUCCEEDS; the inner shell lands in the sandbox. ---
p = subprocess.run(["/usr/bin/bwrap"] + BWRAP_ARGS +
                   ["--", "/bin/sh", "-c", "echo W2B-OK; cat /proc/self/attr/current"],
                   capture_output=True, text=True)
check("W2b-exec-bwrap-mount-capable",
      p.returncode == 0 and "W2B-OK" in p.stdout and SANDBOX in p.stdout,
      "rc=%d out=%r err=%r" % (p.returncode, p.stdout[:120], (p.stderr or "")[:120]))

# --- W3: copy of bwrap at /tmp/mybwrap -> no px rule -> inherits worker ->
#     bwrap setup FAILS (mount operations denied). ---
shutil.copyfile("/usr/bin/bwrap", "/tmp/mybwrap")
os.chmod("/tmp/mybwrap", 0o755)
q = subprocess.run(["/tmp/mybwrap"] + BWRAP_ARGS + ["--", "/bin/true"],
                   capture_output=True, text=True)
check("W3-copied-bwrap-stays-confined", q.returncode != 0,
      "rc=%d err=%r" % (q.returncode, (q.stderr or "")[:160]))

# --- W6: bwrap execs python3 DIRECTLY -> catch-all px -> sandbox profile. ---
r = subprocess.run(["/usr/bin/bwrap"] + BWRAP_ARGS +
                   ["--", "/usr/bin/python3", "-c",
                    "print(open('/proc/self/attr/current').read().strip())"],
                   capture_output=True, text=True)
check("W6-bwrap-exec-python-lands-in-sandbox",
      r.returncode == 0 and r.stdout.strip() == SANDBOX,
      "rc=%d out=%r" % (r.returncode, r.stdout[:120]))

# --- W4/W5: chained sandbox-side probe (w-probe.py: P8 nested-bwrap-denied,
#     P10 clone-confined). The probe prints its own PROBE-SUMMARY. ---
s = subprocess.run(["/usr/bin/bwrap"] + BWRAP_ARGS +
                   ["--", "/bin/sh", "-c", "python3 /w-probe.py"])
if s.returncode != 0:
    results.append(False)
    print("FAIL probe-chain :: probe rc=%d" % s.returncode, flush=True)

print("W-MATRIX:", "PASS" if all(results) else "FAIL", flush=True)
sys.exit(0 if all(results) else 1)
