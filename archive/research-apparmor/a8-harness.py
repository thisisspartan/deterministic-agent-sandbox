# A8 harness (rev8, operator review #7): runs OUTSIDE bwrap as the container's
# PID1. It is python3: the entry profile has NO px rule for python3 -> the
# harness STAYS in the entry profile (inheritance). This is verified, not
# assumed: the harness first prints its own profile; the test script requires
# OUTER-PROFILE=<entry>. /bin/sh is NOT used as the outer process: every shell
# has a px rule -> sandbox, and a shell in the sandbox profile cannot exec a
# mount-capable bwrap (that was the rev7 contradiction).
# The harness then execs bwrap: the entry profile pins /usr/bin/bwrap
# px -> entry, so bwrap stays mount-capable through setup. The untrusted
# command (shell -> python3 /probe.py) runs INSIDE bwrap and must land in the
# sandbox profile (probe P1/P9); nested bwrap from the sandbox stays denied
# (probe P8).
#
# rev12 (operator review #11): entry-profile bypass test. The entry profile is
# mount-capable BY DESIGN (bwrap needs it); the question is whether a child
# created by a direct clone() with namespace flags stays confined. Expected:
#   E1  direct mount, no new namespace      -> EACCES (AppArmor mediates before
#       the capability check; no rule for /tmp/escape-e1/)
#   E3  clone(CLONE_NEWUSER|CLONE_NEWNS|CLONE_NEWPID|SIGCHLD = 805437457) —
#       exactly the flag combination allowed by the pinned seccomp (v-cli3.json).
#       The child owns a new userns (full caps there) + new mountns + new pidns
#       and inherits the entry profile (no exec transition). Inside it:
#         E3-DENY   mount tmpfs at /tmp/escape-test/ (no rule) -> EACCES
#         E3-CONTROL mount tmpfs at /tmp/ (entry rule allows)  -> OK
#           (proves the child HAS mount capability: a DENY is then AppArmor,
#            not capabilities)
#         E3-PROFILE /proc/self/attr/current                    -> entry profile
# Any unexpected OK on DENY / unconfined profile = bypass -> CLONE-TEST: FAIL
# (the test script aborts on a missing CLONE-TEST: PASS). No widening anywhere.
import ctypes, mmap, os, subprocess, sys

libc = ctypes.CDLL("libc.so.6", use_errno=True)
MS_NOSUID, MS_NODEV = 2, 4
CLONE_FLAGS = 805437457  # CLONE_NEWUSER|CLONE_NEWNS|CLONE_NEWPID|SIGCHLD
ENTRY = "stanok-bwrap-x1a-test"

def out(s):
    os.write(1, (s + "\n").encode())

def errno_name():
    e = ctypes.get_errno()
    return {1: "EPERM", 13: "EACCES", 2: "ENOENT", 17: "EEXIST"}.get(e, str(e))

def mkdir_quiet(path):
    try:
        os.mkdir(path)
    except FileExistsError:
        pass

def try_mount(target):
    r = libc.mount(b"tmpfs", target.encode(), b"tmpfs",
                   ctypes.c_ulong(MS_NOSUID | MS_NODEV), None)
    if r == 0:
        return "OK"
    return errno_name()

print("OUTER-PROFILE=" + open("/proc/self/attr/current").read().strip(), flush=True)

# --- E1: direct mount from the entry profile, no new namespace. ---
mkdir_quiet(b"/tmp/escape-e1")
e1 = try_mount("/tmp/escape-e1")
out("CLONE-TEST E1: " + e1 + " (expected EACCES)")

# --- E3: direct clone() with namespace flags; child stays confined. ---
r_fd, w_fd = os.pipe()

def child_fn(_arg):
    ok = True
    prof = open("/proc/self/attr/current").read().strip()
    out("CLONE-TEST E3-PROFILE=" + prof + " (expected " + ENTRY + ")")
    ok = ok and prof == ENTRY
    mkdir_quiet(b"/tmp/escape-test")
    deny = try_mount("/tmp/escape-test")   # BEFORE the control mount: the control
    out("CLONE-TEST E3-DENY: " + deny + " (expected EACCES)")  # mount shadows /tmp
    ok = ok and deny == "EACCES"
    ctl = try_mount("/tmp")
    out("CLONE-TEST E3-CONTROL: " + ctl + " (expected OK)")
    ok = ok and ctl == "OK"
    os.write(w_fd, b"P" if ok else b"F")
    os._exit(0)
    return 0

STACK = 1 << 20
mm = mmap.mmap(-1, STACK)
top = ctypes.addressof(ctypes.c_char.from_buffer(mm)) + STACK
cb = ctypes.CFUNCTYPE(ctypes.c_int, ctypes.c_void_p)(child_fn)
libc.clone.restype = ctypes.c_int
pid = libc.clone(cb, ctypes.c_void_p(top), ctypes.c_int(CLONE_FLAGS), ctypes.c_void_p(0))
if pid < 0:
    out("CLONE-TEST: FAIL (clone() blocked: " + errno_name() + ")")
    sys.exit(1)
os.waitpid(pid, 0)
verdict = os.read(r_fd, 1)
if verdict == b"P" and e1 == "EACCES":
    out("CLONE-TEST: PASS")
else:
    out("CLONE-TEST: FAIL (E1=" + e1 + " child=" + verdict.decode(errors="replace") + ")")
    sys.exit(1)

p = subprocess.run(["bwrap", "--ro-bind", "/", "/", "--dev", "/dev", "--proc", "/proc",
                    "--new-session", "--die-with-parent", "--unshare-user",
                    "--unshare-pid", "--unshare-net",
                    "--", "/bin/sh", "-c", "python3 /probe.py"])
sys.exit(p.returncode)
