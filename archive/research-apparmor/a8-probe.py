# A8 probe: runs INSIDE the bwrap sandbox (test profiles + v-cli3 seccomp).
# Every check prints PASS/FAIL; exit 1 if any FAIL. No auto-widening.
import ctypes, os, sys, subprocess

libc = ctypes.CDLL("libc.so.6", use_errno=True)
NEWUSER = 0x10000000
NEWNS = 0x00020000
results = []

def check(name, cond, detail):
    results.append(cond)
    print(("PASS " if cond else "FAIL ") + name + " :: " + detail)

# P1: actual AppArmor profile of the sandboxed shell
prof = open("/proc/self/attr/current").read().strip()
check("P1-bash-profile-is-sandbox", prof == "stanok-sandbox-x1a-test", prof)

# P2: mount denied (EPERM)
r = libc.mount(b"tmpfs", b"/tmp", b"tmpfs", 0, None)
e = ctypes.get_errno()
check("P2-mount-denied", r != 0 and e == 1, "rc=%d errno=%d" % (r, e))

# P3: unshare(CLONE_NEWUSER) allowed (seccomp EQ 0x10000000)
r = libc.unshare(NEWUSER)
e = ctypes.get_errno()
check("P3-unshare-newuser-allowed", r == 0, "rc=%d errno=%d" % (r, e))

# P4: after nested userns, mount STILL denied (no extended mount perms via nested userns)
r = libc.mount(b"tmpfs", b"/tmp", b"tmpfs", 0, None)
e = ctypes.get_errno()
check("P4-mount-after-newuser-denied", r != 0 and e == 1, "rc=%d errno=%d" % (r, e))

# P5: unshare(CLONE_NEWUSER|CLONE_NEWNS) denied (seccomp default ERRNO)
r = libc.unshare(NEWUSER | NEWNS)
e = ctypes.get_errno()
check("P5-unshare-newns-denied", r != 0 and e == 1, "rc=%d errno=%d" % (r, e))

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
check("P6-clone3-denied", r != 0, "rc=%d errno=%d" % (r, e))

# P7: setns denied for the untrusted command (seccomp: setns ALLOW only with CAP_SYS_ADMIN).
# Mode-aware detail: strict mode (--proc + --unshare-pid) gives a fresh procfs where
# /proc/1 IS the sandbox's own init -> outer mount ns is unreachable from the sandbox
# (a stronger property); weaker mode: /proc/1 is the container's outer sh -> real setns test.
try:
    outer = os.readlink("/proc/1/ns/mnt")
    selfns = os.readlink("/proc/self/ns/mnt")
    mode = "outer-unreachable(fresh-procfs)" if outer == selfns else "outer-ns-reachable"
    fd = os.open("/proc/1/ns/mnt", os.O_RDONLY)
    r = libc.setns(fd, NEWNS)
    e = ctypes.get_errno()
    os.close(fd)
    check("P7-setns-denied", r != 0, "%s rc=%d errno=%d" % (mode, r, e))
except OSError as ex:
    check("P7-setns-denied", True, "open denied errno=%d" % ex.errno)

# P8: nested bwrap denied (needs CLONE_NEWNS)
p = subprocess.run(["bwrap", "--ro-bind", "/", "/", "--dev", "/dev", "--new-session",
                    "--die-with-parent", "--unshare-user", "--unshare-pid",
                    "--unshare-net", "--", "/bin/true"])
check("P8-nested-bwrap-denied", p.returncode != 0, "rc=%d" % p.returncode)

# P9: python3 (no px rule) inherits the sandbox profile — no bypass path
prof2 = subprocess.run(["python3", "-c", "print(open('/proc/self/attr/current').read())"],
                       capture_output=True, text=True).stdout.strip()
check("P9-python-inherits-sandbox", prof2 == "stanok-sandbox-x1a-test", prof2)

print("A8-SUMMARY:", "PASS" if all(results) else "FAIL")
sys.exit(0 if all(results) else 1)
