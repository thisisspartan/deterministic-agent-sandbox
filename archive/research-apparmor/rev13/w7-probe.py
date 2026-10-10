# W7 probe (operator review #13): from the SANDBOX profile, attempts to interact
# with the bwrap process, which retains the mount-capable bwrap profile.
# Expected result: DENIAL on every attempt. Runs as the sandbox command in BOTH
# A7 modes; the target is PID 1 in both:
#   strict : --proc + --unshare-pid -> fresh procfs/pidns, bwrap IS PID 1 there.
#   weaker : no --proc -> /proc is the container's procfs; the container's PID 1
#            IS bwrap (docker runs bwrap as the container command).
# Attribution (review #13 task 3): the test script sets Yama ptrace_scope=0 for
# the W7 window and restores it; seccomp v-cli3.json ALLOWs ptrace,
# process_vm_readv, process_vm_writev unconditionally (minKernel 4.8); tracer and
# target share uid 1000 (DAC allows). With C1 passing, the only remaining gate
# that can deny is AppArmor.
# C1 control: PTRACE_ATTACH to the probe's OWN child (fork -> same profile,
# no exec) MUST succeed — proves ptrace is not blocked by another mechanism and
# the denial is specific to the cross-profile channel.
import ctypes, os, sys, time

libc = ctypes.CDLL("libc.so.6", use_errno=True)
PTRACE_ATTACH, PTRACE_DETACH = 10, 17
SANDBOX = "stanok-sandbox-x1a-test"
results = []

def check(name, cond, detail):
    results.append(cond)
    print(("PASS " if cond else "FAIL ") + name + " :: " + detail, flush=True)

def errno_name():
    e = ctypes.get_errno()
    return {1: "EPERM", 13: "EACCES", 2: "ENOENT"}.get(e, str(e))

libc.ptrace.restype = ctypes.c_long
libc.ptrace.argtypes = [ctypes.c_long, ctypes.c_long, ctypes.c_void_p, ctypes.c_void_p]

# W7-P: own profile must be the sandbox profile (the test is meaningless otherwise)
prof = open("/proc/self/attr/current").read().strip()
check("W7-P-own-profile-sandbox", prof == SANDBOX, prof)

# W7-T: target = PID 1, verified to be the bwrap process (both modes)
try:
    comm = open("/proc/1/comm").read().strip()
except OSError as ex:
    comm = ""
check("W7-T-target-is-bwrap", comm == "bwrap", "comm=%r" % comm)
target = 1

# C1 control: ptrace own child (same profile via fork, no exec) -> ALLOWED.
pid = os.fork()
if pid == 0:
    time.sleep(3)
    os._exit(0)
r = libc.ptrace(PTRACE_ATTACH, ctypes.c_long(pid), None, None)
e = errno_name()
if r == 0:
    os.waitpid(pid, 0)
    libc.ptrace(PTRACE_DETACH, ctypes.c_long(pid), None, None)
    os.kill(pid, 9)
check("C1-ptrace-own-child-allowed", r == 0, "rc=%d errno=%s" % (r, e))

# W7a: PTRACE_ATTACH to the bwrap process -> DENIED
r = libc.ptrace(PTRACE_ATTACH, ctypes.c_long(target), None, None)
e = errno_name()
if r == 0:
    os.waitpid(target, 0)
    libc.ptrace(PTRACE_DETACH, ctypes.c_long(target), None, None)
check("W7a-ptrace-attach-bwrap-denied", r != 0, "rc=%d errno=%s" % (r, e))

# W7b: read /proc/1/mem (mediated by ptrace read permission) -> DENIED
try:
    fd = os.open("/proc/1/mem", os.O_RDONLY)
    data = os.read(fd, 16)
    os.close(fd)
    check("W7b-proc-mem-denied", False, "read %d bytes" % len(data))
except OSError as ex:
    check("W7b-proc-mem-denied", True,
          "errno=%s" % {1: "EPERM", 13: "EACCES"}.get(ex.errno, ex.errno))

# W7c: process_vm_readv on the bwrap process -> DENIED
class IOV(ctypes.Structure):
    _fields_ = [("iov_base", ctypes.c_void_p), ("iov_len", ctypes.c_size_t)]
buf = ctypes.create_string_buffer(16)
local = IOV(ctypes.cast(buf, ctypes.c_void_p), 16)
remote = IOV(ctypes.c_void_p(0x1000), 16)
libc.process_vm_readv.restype = ctypes.c_ssize_t
r = libc.process_vm_readv(ctypes.c_long(target), ctypes.byref(local), 1,
                          ctypes.byref(remote), 1, 0)
e = errno_name()
check("W7c-process_vm_readv-denied", r < 0, "rc=%d errno=%s" % (r, e))

print("W7-SUMMARY:", "PASS" if all(results) else "FAIL", flush=True)
sys.exit(0 if all(results) else 1)
