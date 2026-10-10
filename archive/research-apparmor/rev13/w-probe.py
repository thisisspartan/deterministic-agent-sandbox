# W-probe (rev14, operator review #14): runs INSIDE the bwrap sandbox (test
# profiles + v-cli3 seccomp), chained by w-harness.py. Covers the sandbox side of
# the W-matrix: W4 = P8 (nested bwrap from the sandbox stays confined), W5 = P10
# (namespace-clone child inherits the sandbox profile). Every check prints
# PASS/FAIL; exit 1 if any FAIL. No auto-widening.
# rev14 corrections (latent defects of the deferred a8-probe.py, fixed here):
#   P2/P4 expect EACCES(13), NOT EPERM(1): AppArmor mediates sb_mount BEFORE the
#   capability check, so EACCES is the AppArmor signature; EPERM would mean the
#   denial came from missing capabilities (the test would not prove AppArmor).
#   P5/P6 gate on DENIAL (rc != 0): the denial is produced by the seccomp default
#   ERRNO action, whose errno value is a seccomp detail, not the property under
#   test (the property is "denied").
import ctypes, mmap, os, subprocess, sys

libc = ctypes.CDLL("libc.so.6", use_errno=True)
NEWUSER = 0x10000000
NEWNS = 0x00020000
CLONE_FLAGS = 805437457  # CLONE_NEWUSER|CLONE_NEWNS|CLONE_NEWPID|SIGCHLD (pinned seccomp)
SANDBOX = "stanok-sandbox-x1a-test"
results = []

def check(name, cond, detail):
    results.append(cond)
    print(("PASS " if cond else "FAIL ") + name + " :: " + detail, flush=True)

def errno_name_of(e):
    return {1: "EPERM", 13: "EACCES", 2: "ENOENT", 38: "ENOSYS"}.get(e, str(e))

def errno_name():
    return errno_name_of(ctypes.get_errno())

# P1: actual AppArmor profile of the sandboxed shell
prof = open("/proc/self/attr/current").read().strip()
check("P1-bash-profile-is-sandbox", prof == SANDBOX, prof)

# P2: mount denied BY APPARMOR (EACCES, not EPERM)
r = libc.mount(b"tmpfs", b"/tmp", b"tmpfs", 0, None)
e = ctypes.get_errno()
check("P2-mount-denied-EACCES", r != 0 and e == 13, "rc=%d errno=%s" % (r, errno_name()))

# P3: unshare(CLONE_NEWUSER) allowed (seccomp EQ 0x10000000)
r = libc.unshare(NEWUSER)
e = ctypes.get_errno()
check("P3-unshare-newuser-allowed", r == 0, "rc=%d errno=%s" % (r, errno_name()))

# P4: after nested userns, mount STILL denied by AppArmor (EACCES) — no extended
# mount perms via nested userns.
r = libc.mount(b"tmpfs", b"/tmp", b"tmpfs", 0, None)
e = ctypes.get_errno()
check("P4-mount-after-newuser-denied-EACCES", r != 0 and e == 13, "rc=%d errno=%s" % (r, errno_name()))

# P5: unshare(CLONE_NEWUSER|CLONE_NEWNS) denied (seccomp default ERRNO)
r = libc.unshare(NEWUSER | NEWNS)
e = ctypes.get_errno()
check("P5-unshare-newns-denied", r != 0, "rc=%d errno=%s" % (r, errno_name()))

# P6: clone3 with the same flags denied (v-cli3.json: explicit ERRNO(38) without CAP_SYS_ADMIN)
class CA(ctypes.Structure):
    _fields_ = [("flags", ctypes.c_ulonglong), ("pidfd", ctypes.c_ulonglong),
                ("child_tid", ctypes.c_ulonglong), ("parent_tid", ctypes.c_ulonglong),
                ("exit_signal", ctypes.c_uint), ("stack", ctypes.c_ulonglong),
                ("stack_size", ctypes.c_ulonglong), ("tls", ctypes.c_ulonglong),
                ("set_tid", ctypes.c_ulonglong), ("set_tid_size", ctypes.c_size_t),
                ("cgroup", ctypes.c_ulonglong)]
ca = CA()
ca.flags = NEWUSER | NEWNS
r = libc.syscall(435, ctypes.byref(ca), ctypes.c_size_t(ctypes.sizeof(CA)))
e = ctypes.get_errno()
check("P6-clone3-denied", r != 0, "rc=%d errno=%s" % (r, errno_name()))

# P7: setns denied for the untrusted command (seccomp: setns ALLOW only with CAP_SYS_ADMIN).
# Mode-aware detail: strict mode (--proc + --unshare-pid) gives a fresh procfs where
# /proc/1 IS the sandbox's own init -> outer mount ns is unreachable from the sandbox
# (a stronger property); weaker mode: /proc/1 is the container's outer process -> real setns test.
try:
    outer = os.readlink("/proc/1/ns/mnt")
    selfns = os.readlink("/proc/self/ns/mnt")
    mode = "outer-unreachable(fresh-procfs)" if outer == selfns else "outer-ns-reachable"
    fd = os.open("/proc/1/ns/mnt", os.O_RDONLY)
    r = libc.setns(fd, NEWNS)
    e = ctypes.get_errno()
    os.close(fd)
    check("P7-setns-denied", r != 0, "%s rc=%d errno=%s" % (mode, r, errno_name()))
except OSError as ex:
    check("P7-setns-denied", True, "open denied errno=%s" % errno_name_of(ex.errno))

# P8 (W4): nested bwrap from the sandbox DENIED — the sandbox profile's explicit
# '/usr/bin/bwrap px -> sandbox' keeps it confined; its mount operations are
# denied there. rc != 0 is the gate; the script captures the AppArmor audit
# naming the sandbox profile as corroboration.
p = subprocess.run(["bwrap", "--ro-bind", "/", "/", "--dev", "/dev", "--new-session",
                    "--die-with-parent", "--unshare-user", "--unshare-pid",
                    "--unshare-net", "--", "/bin/true"])
check("P8-nested-bwrap-denied", p.returncode != 0, "rc=%d" % p.returncode)

# P9: python3 (no px rule) inherits the sandbox profile — no bypass path
prof2 = subprocess.run(["python3", "-c", "print(open('/proc/self/attr/current').read())"],
                       capture_output=True, text=True).stdout.strip()
check("P9-python-inherits-sandbox", prof2 == SANDBOX, prof2)

# P10 (W5): namespace-clone from the sandbox: the child owns a new userns (full
# caps there) + new mountns + new pidns, INHERITS the sandbox profile (no exec
# transition) -> mount STILL EACCES (caps present, AppArmor denies).
r_fd, w_fd = os.pipe()

def child_fn(_arg):
    p = open("/proc/self/attr/current").read().strip()
    try:
        os.mkdir("/tmp/escape-w5")
    except FileExistsError:
        pass
    r = libc.mount(b"tmpfs", b"/tmp/escape-w5", b"tmpfs", 0, None)
    m = "OK" if r == 0 else errno_name_of(ctypes.get_errno())
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
    check("P10-clone-child-confined", False, "clone() blocked: " + errno_name())
else:
    os.waitpid(pid, 0)
    got = os.read(r_fd, 256).decode(errors="replace")
    cp, cm = (got.split("|") + ["", ""])[:2]
    check("P10-clone-child-confined", cp == SANDBOX and cm == "EACCES",
          "child profile=%s mount=%s (caps present in new userns)" % (cp, cm))

print("PROBE-SUMMARY:", "PASS" if all(results) else "FAIL", flush=True)
sys.exit(0 if all(results) else 1)
