/\* bubblewrap
\* Copyright (C) 2016 Alexander Larsson
\* SPDX-License-Identifier: LGPL-2.0-or-later
\*
\* This program is free software; you can redistribute it and/or
\* modify it under the terms of the GNU Lesser General Public
\* License as published by the Free Software Foundation; either
\* version 2 of the License, or (at your option) any later version.
\*
\* This library is distributed in the hope that it will be useful,
\* but WITHOUT ANY WARRANTY; without even the implied warranty of
\* MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU
\* Lesser General Public License for more details.
\*
\* You should have received a copy of the GNU Lesser General Public
\* License along with this library. If not, see .
\*
\*/
#include "config.h"
#include 
#include 
#include 
#include 
#include 
#include 
#include 
#include 
#include 
#include 
#include 
#include 
#include 
#include 
#include 
#include 
#include "utils.h"
#include "network.h"
#include "bind-mount.h"
#ifndef CLONE\_NEWCGROUP
#define CLONE\_NEWCGROUP 0x02000000 /\* New cgroup namespace \*/
#endif
#ifndef TEMP\_FAILURE\_RETRY
#define TEMP\_FAILURE\_RETRY(expression) \
(\_\_extension\_\_ \
({ long int \_\_result; \
do \_\_result = (long int) (expression); \
while (\_\_result == -1L && errno == EINTR); \
\_\_result; }))
#endif
/\* We limit the size of a tmpfs to half the architecture's address space,
\* to avoid hitting arbitrary limits in the kernel.
\* For example, on at least one x86\_64 machine, the actual limit seems to be
\* 2^64 - 2^12. \*/
#define MAX\_TMPFS\_BYTES ((size\_t) (SIZE\_MAX >> 1))
/\* Globals to avoid having to use getuid(), since the uid/gid changes during runtime \*/
static uid\_t real\_uid;
static gid\_t real\_gid;
static uid\_t overflow\_uid;
static gid\_t overflow\_gid;
static bool is\_privileged; /\* See acquire\_privs() \*/
static const char \*argv0;
static const char \*host\_tty\_dev;
static int proc\_fd = -1;
static const char \*opt\_exec\_label = NULL;
static const char \*opt\_file\_label = NULL;
static bool opt\_as\_pid\_1;
const char \*opt\_chdir\_path = NULL;
bool opt\_assert\_userns\_disabled = FALSE;
bool opt\_disable\_userns = FALSE;
bool opt\_unshare\_user = FALSE;
bool opt\_unshare\_user\_try = FALSE;
bool opt\_unshare\_pid = FALSE;
bool opt\_unshare\_ipc = FALSE;
bool opt\_unshare\_net = FALSE;
bool opt\_unshare\_uts = FALSE;
bool opt\_unshare\_cgroup = FALSE;
bool opt\_unshare\_cgroup\_try = FALSE;
bool opt\_needs\_devpts = FALSE;
bool opt\_new\_session = FALSE;
bool opt\_die\_with\_parent = FALSE;
uid\_t opt\_sandbox\_uid = -1;
gid\_t opt\_sandbox\_gid = -1;
int opt\_sync\_fd = -1;
int opt\_block\_fd = -1;
int opt\_userns\_block\_fd = -1;
int opt\_info\_fd = -1;
int opt\_json\_status\_fd = -1;
int opt\_seccomp\_fd = -1;
const char \*opt\_sandbox\_hostname = NULL;
char \*opt\_args\_data = NULL; /\* owned \*/
int opt\_userns\_fd = -1;
int opt\_userns2\_fd = -1;
int opt\_pidns\_fd = -1;
int next\_perms = -1;
size\_t next\_size\_arg = 0;
#define CAP\_TO\_MASK\_0(x) (1L << ((x) & 31))
#define CAP\_TO\_MASK\_1(x) CAP\_TO\_MASK\_0(x - 32)
typedef struct \_NsInfo NsInfo;
struct \_NsInfo {
const char \*name;
bool \*do\_unshare;
ino\_t id;
};
static NsInfo ns\_infos[] = {
{"cgroup", &opt\_unshare\_cgroup, 0},
{"ipc", &opt\_unshare\_ipc, 0},
{"mnt", NULL, 0},
{"net", &opt\_unshare\_net, 0},
{"pid", &opt\_unshare\_pid, 0},
/\* user namespace info omitted because it
\* is not (yet) valid when we obtain the
\* namespace info (get un-shared later) \*/
{"uts", &opt\_unshare\_uts, 0},
{NULL, NULL, 0}
};
typedef enum {
SETUP\_BIND\_MOUNT,
SETUP\_RO\_BIND\_MOUNT,
SETUP\_DEV\_BIND\_MOUNT,
SETUP\_MOUNT\_PROC,
SETUP\_MOUNT\_DEV,
SETUP\_MOUNT\_TMPFS,
SETUP\_MOUNT\_MQUEUE,
SETUP\_MAKE\_DIR,
SETUP\_MAKE\_FILE,
SETUP\_MAKE\_BIND\_FILE,
SETUP\_MAKE\_RO\_BIND\_FILE,
SETUP\_MAKE\_SYMLINK,
SETUP\_REMOUNT\_RO\_NO\_RECURSIVE,
SETUP\_SET\_HOSTNAME,
SETUP\_CHMOD,
} SetupOpType;
typedef enum {
NO\_CREATE\_DEST = (1 << 0),
ALLOW\_NOTEXIST = (2 << 0),
} SetupOpFlag;
typedef struct \_SetupOp SetupOp;
struct \_SetupOp
{
SetupOpType type;
const char \*source;
const char \*dest;
int fd;
SetupOpFlag flags;
int perms;
size\_t size; /\* number of bytes, zero means unset/default \*/
SetupOp \*next;
};
typedef struct \_LockFile LockFile;
struct \_LockFile
{
const char \*path;
int fd;
LockFile \*next;
};
enum {
PRIV\_SEP\_OP\_DONE,
PRIV\_SEP\_OP\_BIND\_MOUNT,
PRIV\_SEP\_OP\_PROC\_MOUNT,
PRIV\_SEP\_OP\_TMPFS\_MOUNT,
PRIV\_SEP\_OP\_DEVPTS\_MOUNT,
PRIV\_SEP\_OP\_MQUEUE\_MOUNT,
PRIV\_SEP\_OP\_REMOUNT\_RO\_NO\_RECURSIVE,
PRIV\_SEP\_OP\_SET\_HOSTNAME,
};
typedef struct
{
uint32\_t op;
uint32\_t flags;
uint32\_t perms;
size\_t size\_arg;
uint32\_t arg1\_offset;
uint32\_t arg2\_offset;
} PrivSepOp;
/\*
\* DEFINE\_LINKED\_LIST:
\* @Type: A struct with a `Type \*next` member
\* @name: Used to form the names of variables and functions
\*
\* Define a global linked list of @Type structures, with pointers
\* `NAMEs` to the head of the list and `last\_NAME` to the tail of the
\* list.
\*
\* A new zero-filled item can be allocated and appended to the list
\* by calling `\_NAME\_append\_new()`, which returns the new item.
\*/
#define DEFINE\_LINKED\_LIST(Type, name) \
static Type \*name ## s = NULL; \
static Type \*last\_ ## name = NULL; \
\
static inline Type \* \
\_ ## name ## \_append\_new (void) \
{ \
Type \*self = xcalloc (sizeof (Type)); \
\
if (last\_ ## name != NULL) \
last\_ ## name ->next = self; \
else \
name ## s = self; \
\
last\_ ## name = self; \
return self; \
}
DEFINE\_LINKED\_LIST (SetupOp, op)
static SetupOp \*
setup\_op\_new (SetupOpType type)
{
SetupOp \*op = \_op\_append\_new ();
op->type = type;
op->fd = -1;
op->flags = 0;
return op;
}
DEFINE\_LINKED\_LIST (LockFile, lock\_file)
static LockFile \*
lock\_file\_new (const char \*path)
{
LockFile \*lock = \_lock\_file\_append\_new ();
lock->path = path;
return lock;
}
typedef struct \_SeccompProgram SeccompProgram;
struct \_SeccompProgram
{
struct sock\_fprog program;
SeccompProgram \*next;
};
DEFINE\_LINKED\_LIST (SeccompProgram, seccomp\_program)
static SeccompProgram \*
seccomp\_program\_new (int \*fd)
{
SeccompProgram \*self = \_seccomp\_program\_append\_new ();
cleanup\_free char \*data = NULL;
size\_t len;
data = load\_file\_data (\*fd, &len);
if (data == NULL)
die\_with\_error ("Can't read seccomp data");
close (\*fd);
\*fd = -1;
if (len % 8 != 0)
die ("Invalid seccomp data, must be multiple of 8");
self->program.len = len / 8;
self->program.filter = (struct sock\_filter \*) steal\_pointer (&data);
return self;
}
static void
seccomp\_programs\_apply (void)
{
SeccompProgram \*program;
for (program = seccomp\_programs; program != NULL; program = program->next)
{
if (prctl (PR\_SET\_SECCOMP, SECCOMP\_MODE\_FILTER, &program->program) != 0)
{
if (errno == EINVAL)
die ("Unable to set up system call filtering as requested: "
"prctl(PR\_SET\_SECCOMP) reported EINVAL. "
"(Hint: this requires a kernel configured with "
"CONFIG\_SECCOMP and CONFIG\_SECCOMP\_FILTER.)");
die\_with\_error ("prctl(PR\_SET\_SECCOMP)");
}
}
}
static void
usage (int ecode, FILE \*out)
{
fprintf (out, "usage: %s [OPTIONS...] [--] COMMAND [ARGS...]\n\n", argv0 ? argv0 : "bwrap");
fprintf (out,
" --help Print this help\n"
" --version Print version\n"
" --args FD Parse NUL-separated args from FD\n"
" --unshare-all Unshare every namespace we support by default\n"
" --share-net Retain the network namespace (can only combine with --unshare-all)\n"
" --unshare-user Create new user namespace (may be automatically implied if not setuid)\n"
" --unshare-user-try Create new user namespace if possible else continue by skipping it\n"
" --unshare-ipc Create new ipc namespace\n"
" --unshare-pid Create new pid namespace\n"
" --unshare-net Create new network namespace\n"
" --unshare-uts Create new uts namespace\n"
" --unshare-cgroup Create new cgroup namespace\n"
" --unshare-cgroup-try Create new cgroup namespace if possible else continue by skipping it\n"
" --userns FD Use this user namespace (cannot combine with --unshare-user)\n"
" --userns2 FD After setup switch to this user namespace, only useful with --userns\n"
" --disable-userns Disable further use of user namespaces inside sandbox\n"
" --assert-userns-disabled Fail unless further use of user namespace inside sandbox is disabled\n"
" --pidns FD Use this pid namespace (as parent namespace if using --unshare-pid)\n"
" --uid UID Custom uid in the sandbox (requires --unshare-user or --userns)\n"
" --gid GID Custom gid in the sandbox (requires --unshare-user or --userns)\n"
" --hostname NAME Custom hostname in the sandbox (requires --unshare-uts)\n"
" --chdir DIR Change directory to DIR\n"
" --clearenv Unset all environment variables\n"
" --setenv VAR VALUE Set an environment variable\n"
" --unsetenv VAR Unset an environment variable\n"
" --lock-file DEST Take a lock on DEST while sandbox is running\n"
" --sync-fd FD Keep this fd open while sandbox is running\n"
" --bind SRC DEST Bind mount the host path SRC on DEST\n"
" --bind-try SRC DEST Equal to --bind but ignores non-existent SRC\n"
" --dev-bind SRC DEST Bind mount the host path SRC on DEST, allowing device access\n"
" --dev-bind-try SRC DEST Equal to --dev-bind but ignores non-existent SRC\n"
" --ro-bind SRC DEST Bind mount the host path SRC readonly on DEST\n"
" --ro-bind-try SRC DEST Equal to --ro-bind but ignores non-existent SRC\n"
" --remount-ro DEST Remount DEST as readonly; does not recursively remount\n"
" --exec-label LABEL Exec label for the sandbox\n"
" --file-label LABEL File label for temporary sandbox content\n"
" --proc DEST Mount new procfs on DEST\n"
" --dev DEST Mount new dev on DEST\n"
" --tmpfs DEST Mount new tmpfs on DEST\n"
" --mqueue DEST Mount new mqueue on DEST\n"
" --dir DEST Create dir at DEST\n"
" --file FD DEST Copy from FD to destination DEST\n"
" --bind-data FD DEST Copy from FD to file which is bind-mounted on DEST\n"
" --ro-bind-data FD DEST Copy from FD to file which is readonly bind-mounted on DEST\n"
" --symlink SRC DEST Create symlink at DEST with target SRC\n"
" --seccomp FD Load and use seccomp rules from FD (not repeatable)\n"
" --add-seccomp-fd FD Load and use seccomp rules from FD (repeatable)\n"
" --block-fd FD Block on FD until some data to read is available\n"
" --userns-block-fd FD Block on FD until the user namespace is ready\n"
" --info-fd FD Write information about the running container to FD\n"
" --json-status-fd FD Write container status to FD as multiple JSON documents\n"
" --new-session Create a new terminal session\n"
" --die-with-parent Kills with SIGKILL child process (COMMAND) when bwrap or bwrap's parent dies.\n"
" --as-pid-1 Do not install a reaper process with PID=1\n"
" --cap-add CAP Add cap CAP when running as privileged user\n"
" --cap-drop CAP Drop cap CAP when running as privileged user\n"
" --perms OCTAL Set permissions of next argument (--bind-data, --file, etc.)\n"
" --size BYTES Set size of next argument (only for --tmpfs)\n"
" --chmod OCTAL PATH Change permissions of PATH (must already exist)\n"
);
exit (ecode);
}
/\* If --die-with-parent was specified, use PDEATHSIG to ensure SIGKILL
\* is sent to the current process when our parent dies.
\*/
static void
handle\_die\_with\_parent (void)
{
if (opt\_die\_with\_parent && prctl (PR\_SET\_PDEATHSIG, SIGKILL, 0, 0, 0) != 0)
die\_with\_error ("prctl");
}
static void
block\_sigchild (void)
{
sigset\_t mask;
int status;
sigemptyset (&mask);
sigaddset (&mask, SIGCHLD);
if (sigprocmask (SIG\_BLOCK, &mask, NULL) == -1)
die\_with\_error ("sigprocmask");
/\* Reap any outstanding zombies that we may have inherited \*/
while (waitpid (-1, &status, WNOHANG) > 0)
;
}
static void
unblock\_sigchild (void)
{
sigset\_t mask;
sigemptyset (&mask);
sigaddset (&mask, SIGCHLD);
if (sigprocmask (SIG\_UNBLOCK, &mask, NULL) == -1)
die\_with\_error ("sigprocmask");
}
/\* Closes all fd:s except 0,1,2 and the passed in array of extra fds \*/
static int
close\_extra\_fds (void \*data, int fd)
{
int \*extra\_fds = (int \*) data;
int i;
for (i = 0; extra\_fds[i] != -1; i++)
if (fd == extra\_fds[i])
return 0;
if (fd <= 2)
return 0;
close (fd);
return 0;
}
static int
propagate\_exit\_status (int status)
{
if (WIFEXITED (status))
return WEXITSTATUS (status);
/\* The process died of a signal, we can't really report that, but we
\* can at least be bash-compatible. The bash manpage says:
\* The return value of a simple command is its
\* exit status, or 128+n if the command is
\* terminated by signal n.
\*/
if (WIFSIGNALED (status))
return 128 + WTERMSIG (status);
/\* Weird? \*/
return 255;
}
static void
dump\_info (int fd, const char \*output, bool exit\_on\_error)
{
size\_t len = strlen (output);
if (write\_to\_fd (fd, output, len))
{
if (exit\_on\_error)
die\_with\_error ("Write to info\_fd");
}
}
static void
report\_child\_exit\_status (int exitc, int setup\_finished\_fd)
{
ssize\_t s;
char data[2];
cleanup\_free char \*output = NULL;
if (opt\_json\_status\_fd == -1 || setup\_finished\_fd == -1)
return;
s = TEMP\_FAILURE\_RETRY (read (setup\_finished\_fd, data, sizeof data));
if (s == -1 && errno != EAGAIN)
die\_with\_error ("read eventfd");
if (s != 1) // Is 0 if pipe closed before exec, is 2 if closed after exec.
return;
output = xasprintf ("{ \"exit-code\": %i }\n", exitc);
dump\_info (opt\_json\_status\_fd, output, FALSE);
close (opt\_json\_status\_fd);
opt\_json\_status\_fd = -1;
close (setup\_finished\_fd);
}
/\* This stays around for as long as the initial process in the app does
\* and when that exits it exits, propagating the exit status. We do this
\* by having pid 1 in the sandbox detect this exit and tell the monitor
\* the exit status via a eventfd. We also track the exit of the sandbox
\* pid 1 via a signalfd for SIGCHLD, and exit with an error in this case.
\* This is to catch e.g. problems during setup. \*/
static int
monitor\_child (int event\_fd, pid\_t child\_pid, int setup\_finished\_fd)
{
int res;
uint64\_t val;
ssize\_t s;
int signal\_fd;
sigset\_t mask;
struct pollfd fds[2];
int num\_fds;
struct signalfd\_siginfo fdsi;
int dont\_close[] = {-1, -1, -1, -1};
int j = 0;
int exitc;
pid\_t died\_pid;
int died\_status;
/\* Close all extra fds in the monitoring process.
Any passed in fds have been passed on to the child anyway. \*/
if (event\_fd != -1)
dont\_close[j++] = event\_fd;
if (opt\_json\_status\_fd != -1)
dont\_close[j++] = opt\_json\_status\_fd;
if (setup\_finished\_fd != -1)
dont\_close[j++] = setup\_finished\_fd;
assert (j < sizeof(dont\_close)/sizeof(\*dont\_close));
fdwalk (proc\_fd, close\_extra\_fds, dont\_close);
sigemptyset (&mask);
sigaddset (&mask, SIGCHLD);
signal\_fd = signalfd (-1, &mask, SFD\_CLOEXEC | SFD\_NONBLOCK);
if (signal\_fd == -1)
die\_with\_error ("Can't create signalfd");
num\_fds = 1;
fds[0].fd = signal\_fd;
fds[0].events = POLLIN;
if (event\_fd != -1)
{
fds[1].fd = event\_fd;
fds[1].events = POLLIN;
num\_fds++;
}
while (1)
{
fds[0].revents = fds[1].revents = 0;
res = poll (fds, num\_fds, -1);
if (res == -1 && errno != EINTR)
die\_with\_error ("poll");
/\* Always read from the eventfd first, if pid 2 died then pid 1 often
\* dies too, and we could race, reporting that first and we'd lose
\* the real exit status. \*/
if (event\_fd != -1)
{
s = read (event\_fd, &val, 8);
if (s == -1 && errno != EINTR && errno != EAGAIN)
die\_with\_error ("read eventfd");
else if (s == 8)
{
exitc = (int) val - 1;
report\_child\_exit\_status (exitc, setup\_finished\_fd);
return exitc;
}
}
/\* We need to read the signal\_fd, or it will keep polling as read,
\* however we ignore the details as we get them from waitpid
\* below anyway \*/
s = read (signal\_fd, &fdsi, sizeof (struct signalfd\_siginfo));
if (s == -1 && errno != EINTR && errno != EAGAIN)
die\_with\_error ("read signalfd");
/\* We may actually get several sigchld compressed into one
SIGCHLD, so we have to handle all of them. \*/
while ((died\_pid = waitpid (-1, &died\_status, WNOHANG)) > 0)
{
/\* We may be getting sigchild from other children too. For instance if
someone created a child process, and then exec:ed bubblewrap. Ignore them \*/
if (died\_pid == child\_pid)
{
exitc = propagate\_exit\_status (died\_status);
report\_child\_exit\_status (exitc, setup\_finished\_fd);
return exitc;
}
}
}
die ("Should not be reached");
return 0;
}
/\* This is pid 1 in the app sandbox. It is needed because we're using
\* pid namespaces, and someone has to reap zombies in it. We also detect
\* when the initial process (pid 2) dies and report its exit status to
\* the monitor so that it can return it to the original spawner.
\*
\* When there are no other processes in the sandbox the wait will return
\* ECHILD, and we then exit pid 1 to clean up the sandbox. \*/
static int
do\_init (int event\_fd, pid\_t initial\_pid)
{
int initial\_exit\_status = 1;
LockFile \*lock;
for (lock = lock\_files; lock != NULL; lock = lock->next)
{
int fd = open (lock->path, O\_RDONLY | O\_CLOEXEC);
if (fd == -1)
die\_with\_error ("Unable to open lock file %s", lock->path);
struct flock l = {
.l\_type = F\_RDLCK,
.l\_whence = SEEK\_SET,
.l\_start = 0,
.l\_len = 0
};
if (fcntl (fd, F\_SETLK, &l) < 0)
die\_with\_error ("Unable to lock file %s", lock->path);
/\* Keep fd open to hang on to lock \*/
lock->fd = fd;
}
/\* Optionally bind our lifecycle to that of the caller \*/
handle\_die\_with\_parent ();
seccomp\_programs\_apply ();
while (TRUE)
{
pid\_t child;
int status;
child = wait (&status);
if (child == initial\_pid)
{
initial\_exit\_status = propagate\_exit\_status (status);
if(event\_fd != -1)
{
uint64\_t val;
int res UNUSED;
val = initial\_exit\_status + 1;
res = write (event\_fd, &val, 8);
/\* Ignore res, if e.g. the parent died and closed event\_fd
we don't want to error out here \*/
}
}
if (child == -1 && errno != EINTR)
{
if (errno != ECHILD)
die\_with\_error ("init wait()");
break;
}
}
/\* Close FDs. \*/
for (lock = lock\_files; lock != NULL; lock = lock->next)
{
if (lock->fd >= 0)
{
close (lock->fd);
lock->fd = -1;
}
}
return initial\_exit\_status;
}
#define CAP\_TO\_MASK\_0(x) (1L << ((x) & 31))
#define CAP\_TO\_MASK\_1(x) CAP\_TO\_MASK\_0(x - 32)
/\* Set if --cap-add or --cap-drop were used \*/
static bool opt\_cap\_add\_or\_drop\_used;
/\* The capability set we'll target, used if above is true \*/
static uint32\_t requested\_caps[2] = {0, 0};
/\* low 32bit caps needed \*/
/\* CAP\_SYS\_PTRACE is needed to dereference the symlinks in /proc//ns/, see namespaces(7) \*/
#define REQUIRED\_CAPS\_0 (CAP\_TO\_MASK\_0 (CAP\_SYS\_ADMIN) | CAP\_TO\_MASK\_0 (CAP\_SYS\_CHROOT) | CAP\_TO\_MASK\_0 (CAP\_NET\_ADMIN) | CAP\_TO\_MASK\_0 (CAP\_SETUID) | CAP\_TO\_MASK\_0 (CAP\_SETGID) | CAP\_TO\_MASK\_0 (CAP\_SYS\_PTRACE))
/\* high 32bit caps needed \*/
#define REQUIRED\_CAPS\_1 0
static void
set\_required\_caps (void)
{
struct \_\_user\_cap\_header\_struct hdr = { \_LINUX\_CAPABILITY\_VERSION\_3, 0 };
struct \_\_user\_cap\_data\_struct data[2] = { { 0 } };
/\* Drop all non-require capabilities \*/
data[0].effective = REQUIRED\_CAPS\_0;
data[0].permitted = REQUIRED\_CAPS\_0;
data[0].inheritable = 0;
data[1].effective = REQUIRED\_CAPS\_1;
data[1].permitted = REQUIRED\_CAPS\_1;
data[1].inheritable = 0;
if (capset (&hdr, data) < 0)
die\_with\_error ("capset failed");
}
static void
drop\_all\_caps (bool keep\_requested\_caps)
{
struct \_\_user\_cap\_header\_struct hdr = { \_LINUX\_CAPABILITY\_VERSION\_3, 0 };
struct \_\_user\_cap\_data\_struct data[2] = { { 0 } };
if (keep\_requested\_caps)
{
/\* Avoid calling capset() unless we need to; currently
\* systemd-nspawn at least is known to install a seccomp
\* policy denying capset() for dubious reasons.
\* 
\*/
if (!opt\_cap\_add\_or\_drop\_used && real\_uid == 0)
{
assert (!is\_privileged);
return;
}
data[0].effective = requested\_caps[0];
data[0].permitted = requested\_caps[0];
data[0].inheritable = requested\_caps[0];
data[1].effective = requested\_caps[1];
data[1].permitted = requested\_caps[1];
data[1].inheritable = requested\_caps[1];
}
if (capset (&hdr, data) < 0)
{
/\* While the above logic ensures we don't call capset() for the primary
\* process unless configured to do so, we still try to drop privileges for
\* the init process unconditionally. Since due to the systemd seccomp
\* filter that will fail, let's just ignore it.
\*/
if (errno == EPERM && real\_uid == 0 && !is\_privileged)
return;
else
die\_with\_error ("capset failed");
}
}
static bool
has\_caps (void)
{
struct \_\_user\_cap\_header\_struct hdr = { \_LINUX\_CAPABILITY\_VERSION\_3, 0 };
struct \_\_user\_cap\_data\_struct data[2] = { { 0 } };
if (capget (&hdr, data) < 0)
die\_with\_error ("capget failed");
return data[0].permitted != 0 || data[1].permitted != 0;
}
/\* Most of the code here is used both to add caps to the ambient capabilities
\* and drop caps from the bounding set. Handle both cases here and add
\* drop\_cap\_bounding\_set/set\_ambient\_capabilities wrappers to facilitate its usage.
\*/
static void
prctl\_caps (uint32\_t \*caps, bool do\_cap\_bounding, bool do\_set\_ambient)
{
unsigned long cap;
/\* We ignore both EINVAL and EPERM, as we are actually relying
\* on PR\_SET\_NO\_NEW\_PRIVS to ensure the right capabilities are
\* available. EPERM in particular can happen with old, buggy
\* kernels. See:
\* https://github.com/projectatomic/bubblewrap/pull/175#issuecomment-278051373
\* https://git.kernel.org/cgit/linux/kernel/git/torvalds/linux.git/commit/security/commoncap.c?id=160da84dbb39443fdade7151bc63a88f8e953077
\*/
for (cap = 0; cap <= CAP\_LAST\_CAP; cap++)
{
bool keep = FALSE;
if (cap < 32)
{
if (CAP\_TO\_MASK\_0 (cap) & caps[0])
keep = TRUE;
}
else
{
if (CAP\_TO\_MASK\_1 (cap) & caps[1])
keep = TRUE;
}
if (keep && do\_set\_ambient)
{
#ifdef PR\_CAP\_AMBIENT
int res = prctl (PR\_CAP\_AMBIENT, PR\_CAP\_AMBIENT\_RAISE, cap, 0, 0);
if (res == -1 && !(errno == EINVAL || errno == EPERM))
die\_with\_error ("Adding ambient capability %ld", cap);
#else
/\* We ignore the EINVAL that results from not having PR\_CAP\_AMBIENT
\* in the current kernel at runtime, so also ignore not having it
\* in the current kernel headers at compile-time \*/
#endif
}
if (!keep && do\_cap\_bounding)
{
int res = prctl (PR\_CAPBSET\_DROP, cap, 0, 0, 0);
if (res == -1 && !(errno == EINVAL || errno == EPERM))
die\_with\_error ("Dropping capability %ld from bounds", cap);
}
}
}
static void
drop\_cap\_bounding\_set (bool drop\_all)
{
if (!drop\_all)
prctl\_caps (requested\_caps, TRUE, FALSE);
else
{
uint32\_t no\_caps[2] = {0, 0};
prctl\_caps (no\_caps, TRUE, FALSE);
}
}
static void
set\_ambient\_capabilities (void)
{
if (is\_privileged)
return;
prctl\_caps (requested\_caps, FALSE, TRUE);
}
/\* This acquires the privileges that the bwrap will need it to work.
\* If bwrap is not setuid, then this does nothing, and it relies on
\* unprivileged user namespaces to be used. This case is
\* "is\_privileged = FALSE".
\*
\* If bwrap is setuid, then we do things in phases.
\* The first part is run as euid 0, but with fsuid as the real user.
\* The second part, inside the child, is run as the real user but with
\* capabilities.
\* And finally we drop all capabilities.
\* The reason for the above dance is to avoid having the setup phase
\* being able to read files the user can't, while at the same time
\* working around various kernel issues. See below for details.
\*/
static void
acquire\_privs (void)
{
uid\_t euid, new\_fsuid;
euid = geteuid ();
/\* Are we setuid ? \*/
if (real\_uid != euid)
{
if (euid != 0)
die ("Unexpected setuid user %d, should be 0", euid);
is\_privileged = TRUE;
/\* We want to keep running as euid=0 until at the clone()
\* operation because doing so will make the user namespace be
\* owned by root, which makes it not ptrace:able by the user as
\* it otherwise would be. After that we will run fully as the
\* user, which is necessary e.g. to be able to read from a fuse
\* mount from the user.
\*
\* However, we don't want to accidentally mis-use euid=0 for
\* escalated filesystem access before the clone(), so we set
\* fsuid to the uid.
\*/
if (setfsuid (real\_uid) < 0)
die\_with\_error ("Unable to set fsuid");
/\* setfsuid can't properly report errors, check that it worked (as per manpage) \*/
new\_fsuid = setfsuid (-1);
if (new\_fsuid != real\_uid)
die ("Unable to set fsuid (was %d)", (int)new\_fsuid);
/\* We never need capabilities after execve(), so lets drop everything from the bounding set \*/
drop\_cap\_bounding\_set (TRUE);
/\* Keep only the required capabilities for setup \*/
set\_required\_caps ();
}
else if (real\_uid != 0 && has\_caps ())
{
/\* We have some capabilities in the non-setuid case, which should not happen.
Probably caused by the binary being setcap instead of setuid which we
don't support anymore \*/
die ("Unexpected capabilities but not setuid, old file caps config?");
}
else if (real\_uid == 0)
{
/\* If our uid is 0, default to inheriting all caps; the caller
\* can drop them via --cap-drop. This is used by at least rpm-ostree.
\* Note this needs to happen before the argument parsing of --cap-drop.
\*/
struct \_\_user\_cap\_header\_struct hdr = { \_LINUX\_CAPABILITY\_VERSION\_3, 0 };
struct \_\_user\_cap\_data\_struct data[2] = { { 0 } };
if (capget (&hdr, data) < 0)
die\_with\_error ("capget (for uid == 0) failed");
requested\_caps[0] = data[0].effective;
requested\_caps[1] = data[1].effective;
}
/\* Else, we try unprivileged user namespaces \*/
}
/\* This is called once we're inside the namespace \*/
static void
switch\_to\_user\_with\_privs (void)
{
/\* If we're in a new user namespace, we got back the bounding set, clear it again \*/
if (opt\_unshare\_user || opt\_userns\_fd != -1)
drop\_cap\_bounding\_set (FALSE);
/\* If we switched to a new user namespace it may allow other uids/gids, so switch to the target one \*/
if (opt\_userns\_fd != -1)
{
if (opt\_sandbox\_uid != real\_uid && setuid (opt\_sandbox\_uid) < 0)
die\_with\_error ("unable to switch to uid %d", opt\_sandbox\_uid);
if (opt\_sandbox\_gid != real\_gid && setgid (opt\_sandbox\_gid) < 0)
die\_with\_error ("unable to switch to gid %d", opt\_sandbox\_gid);
}
if (!is\_privileged)
return;
/\* Tell kernel not clear capabilities when later dropping root uid \*/
if (prctl (PR\_SET\_KEEPCAPS, 1, 0, 0, 0) < 0)
die\_with\_error ("prctl(PR\_SET\_KEEPCAPS) failed");
if (setuid (opt\_sandbox\_uid) < 0)
die\_with\_error ("unable to drop root uid");
/\* Regain effective required capabilities from permitted \*/
set\_required\_caps ();
}
/\* Call setuid() and use capset() to adjust capabilities \*/
static void
drop\_privs (bool keep\_requested\_caps,
bool already\_changed\_uid)
{
assert (!keep\_requested\_caps || !is\_privileged);
/\* Drop root uid \*/
if (is\_privileged && !already\_changed\_uid &&
setuid (opt\_sandbox\_uid) < 0)
die\_with\_error ("unable to drop root uid");
drop\_all\_caps (keep\_requested\_caps);
/\* We don't have any privs now, so mark us dumpable which makes /proc/self be owned by the user instead of root \*/
if (prctl (PR\_SET\_DUMPABLE, 1, 0, 0, 0) != 0)
die\_with\_error ("can't set dumpable");
}
static char \*
get\_newroot\_path (const char \*path)
{
while (\*path == '/')
path++;
return strconcat ("/newroot/", path);
}
static void
write\_uid\_gid\_map (uid\_t sandbox\_uid,
uid\_t parent\_uid,
uid\_t sandbox\_gid,
uid\_t parent\_gid,
pid\_t pid,
bool deny\_groups,
bool map\_root)
{
cleanup\_free char \*uid\_map = NULL;
cleanup\_free char \*gid\_map = NULL;
cleanup\_free char \*dir = NULL;
cleanup\_fd int dir\_fd = -1;
uid\_t old\_fsuid = -1;
if (pid == -1)
dir = xstrdup ("self");
else
dir = xasprintf ("%d", pid);
dir\_fd = openat (proc\_fd, dir, O\_PATH);
if (dir\_fd < 0)
die\_with\_error ("open /proc/%s failed", dir);
if (map\_root && parent\_uid != 0 && sandbox\_uid != 0)
uid\_map = xasprintf ("0 %d 1\n"
"%d %d 1\n", overflow\_uid, sandbox\_uid, parent\_uid);
else
uid\_map = xasprintf ("%d %d 1\n", sandbox\_uid, parent\_uid);
if (map\_root && parent\_gid != 0 && sandbox\_gid != 0)
gid\_map = xasprintf ("0 %d 1\n"
"%d %d 1\n", overflow\_gid, sandbox\_gid, parent\_gid);
else
gid\_map = xasprintf ("%d %d 1\n", sandbox\_gid, parent\_gid);
/\* We have to be root to be allowed to write to the uid map
\* for setuid apps, so temporary set fsuid to 0 \*/
if (is\_privileged)
old\_fsuid = setfsuid (0);
if (write\_file\_at (dir\_fd, "uid\_map", uid\_map) != 0)
die\_with\_error ("setting up uid map");
if (deny\_groups &&
write\_file\_at (dir\_fd, "setgroups", "deny\n") != 0)
{
/\* If /proc/[pid]/setgroups does not exist, assume we are
\* running a linux kernel < 3.19, i.e. we live with the
\* vulnerability known as CVE-2014-8989 in older kernels
\* where setgroups does not exist.
\*/
if (errno != ENOENT)
die\_with\_error ("error writing to setgroups");
}
if (write\_file\_at (dir\_fd, "gid\_map", gid\_map) != 0)
die\_with\_error ("setting up gid map");
if (is\_privileged)
{
setfsuid (old\_fsuid);
if (setfsuid (-1) != real\_uid)
die ("Unable to re-set fsuid");
}
}
static void
privileged\_op (int privileged\_op\_socket,
uint32\_t op,
uint32\_t flags,
uint32\_t perms,
size\_t size\_arg,
const char \*arg1,
const char \*arg2)
{
bind\_mount\_result bind\_result;
char \*failing\_path = NULL;
if (privileged\_op\_socket != -1)
{
uint32\_t buffer[2048]; /\* 8k, but is int32 to guarantee nice alignment \*/
PrivSepOp \*op\_buffer = (PrivSepOp \*) buffer;
size\_t buffer\_size = sizeof (PrivSepOp);
uint32\_t arg1\_offset = 0, arg2\_offset = 0;
/\* We're unprivileged, send this request to the privileged part \*/
if (arg1 != NULL)
{
arg1\_offset = buffer\_size;
buffer\_size += strlen (arg1) + 1;
}
if (arg2 != NULL)
{
arg2\_offset = buffer\_size;
buffer\_size += strlen (arg2) + 1;
}
if (buffer\_size >= sizeof (buffer))
die ("privilege separation operation to large");
op\_buffer->op = op;
op\_buffer->flags = flags;
op\_buffer->perms = perms;
op\_buffer->size\_arg = size\_arg;
op\_buffer->arg1\_offset = arg1\_offset;
op\_buffer->arg2\_offset = arg2\_offset;
if (arg1 != NULL)
strcpy ((char \*) buffer + arg1\_offset, arg1);
if (arg2 != NULL)
strcpy ((char \*) buffer + arg2\_offset, arg2);
if (write (privileged\_op\_socket, buffer, buffer\_size) != buffer\_size)
die ("Can't write to privileged\_op\_socket");
if (read (privileged\_op\_socket, buffer, 1) != 1)
die ("Can't read from privileged\_op\_socket");
return;
}
/\*
\* This runs a privileged request for the unprivileged setup
\* code. Note that since the setup code is unprivileged it is not as
\* trusted, so we need to verify that all requests only affect the
\* child namespace as set up by the privileged parts of the setup,
\* and that all the code is very careful about handling input.
\*
\* This means:
\* \* Bind mounts are safe, since we always use filesystem namespace. They
\* must be recursive though, as otherwise you can use a non-recursive bind
\* mount to access an otherwise over-mounted mountpoint.
\* \* Mounting proc, tmpfs, mqueue, devpts in the child namespace is assumed to
\* be safe.
\* \* Remounting RO (even non-recursive) is safe because it decreases privileges.
\* \* sethostname() is safe only if we set up a UTS namespace
\*/
switch (op)
{
case PRIV\_SEP\_OP\_DONE:
break;
case PRIV\_SEP\_OP\_REMOUNT\_RO\_NO\_RECURSIVE:
bind\_result = bind\_mount (proc\_fd, NULL, arg2, BIND\_READONLY, &failing\_path);
if (bind\_result != BIND\_MOUNT\_SUCCESS)
die\_with\_bind\_result (bind\_result, errno, failing\_path,
"Can't remount readonly on %s", arg2);
assert (failing\_path == NULL); /\* otherwise we would have died \*/
break;
case PRIV\_SEP\_OP\_BIND\_MOUNT:
/\* We always bind directories recursively, otherwise this would let us
access files that are otherwise covered on the host \*/
bind\_result = bind\_mount (proc\_fd, arg1, arg2, BIND\_RECURSIVE | flags, &failing\_path);
if (bind\_result != BIND\_MOUNT\_SUCCESS)
die\_with\_bind\_result (bind\_result, errno, failing\_path,
"Can't bind mount %s on %s", arg1, arg2);
assert (failing\_path == NULL); /\* otherwise we would have died \*/
break;
case PRIV\_SEP\_OP\_PROC\_MOUNT:
if (mount ("proc", arg1, "proc", MS\_NOSUID | MS\_NOEXEC | MS\_NODEV, NULL) != 0)
die\_with\_error ("Can't mount proc on %s", arg1);
break;
case PRIV\_SEP\_OP\_TMPFS\_MOUNT:
{
cleanup\_free char \*mode = NULL;
/\* This check should be unnecessary since we checked this when parsing
\* the --size option as well. However, better be safe than sorry. \*/
if (size\_arg > MAX\_TMPFS\_BYTES)
die\_with\_error ("Specified tmpfs size too large (%zu > %zu)", size\_arg, MAX\_TMPFS\_BYTES);
if (size\_arg != 0)
mode = xasprintf ("mode=%#o,size=%zu", perms, size\_arg);
else
mode = xasprintf ("mode=%#o", perms);
cleanup\_free char \*opt = label\_mount (mode, opt\_file\_label);
if (mount ("tmpfs", arg1, "tmpfs", MS\_NOSUID | MS\_NODEV, opt) != 0)
die\_with\_error ("Can't mount tmpfs on %s", arg1);
break;
}
case PRIV\_SEP\_OP\_DEVPTS\_MOUNT:
if (mount ("devpts", arg1, "devpts", MS\_NOSUID | MS\_NOEXEC,
"newinstance,ptmxmode=0666,mode=620") != 0)
die\_with\_error ("Can't mount devpts on %s", arg1);
break;
case PRIV\_SEP\_OP\_MQUEUE\_MOUNT:
if (mount ("mqueue", arg1, "mqueue", 0, NULL) != 0)
die\_with\_error ("Can't mount mqueue on %s", arg1);
break;
case PRIV\_SEP\_OP\_SET\_HOSTNAME:
/\* This is checked at the start, but lets verify it here in case
something manages to send hacked priv-sep operation requests. \*/
if (!opt\_unshare\_uts)
die ("Refusing to set hostname in original namespace");
if (sethostname (arg1, strlen(arg1)) != 0)
die\_with\_error ("Can't set hostname to %s", arg1);
break;
default:
die ("Unexpected privileged op %d", op);
}
}
/\* This is run unprivileged in the child namespace but can request
\* some privileged operations (also in the child namespace) via the
\* privileged\_op\_socket.
\*/
static void
setup\_newroot (bool unshare\_pid,
int privileged\_op\_socket)
{
SetupOp \*op;
for (op = ops; op != NULL; op = op->next)
{
cleanup\_free char \*source = NULL;
cleanup\_free char \*dest = NULL;
int source\_mode = 0;
int i;
if (op->source &&
op->type != SETUP\_MAKE\_SYMLINK)
{
source = get\_oldroot\_path (op->source);
source\_mode = get\_file\_mode (source);
if (source\_mode < 0)
{
if (op->flags & ALLOW\_NOTEXIST && errno == ENOENT)
continue; /\* Ignore and move on \*/
die\_with\_error("Can't get type of source %s", op->source);
}
}
if (op->dest &&
(op->flags & NO\_CREATE\_DEST) == 0)
{
unsigned parent\_mode = 0755;
/\* If we're creating a file that is inaccessible by the owning group,
\* try to achieve least-astonishment by creating parents also
\* inaccessible by that group. \*/
if (op->perms >= 0 &&
(op->perms & 0070) == 0)
parent\_mode &= ~0050;
/\* The same, but for users other than the owner and group. \*/
if (op->perms >= 0 &&
(op->perms & 0007) == 0)
parent\_mode &= ~0005;
dest = get\_newroot\_path (op->dest);
if (mkdir\_with\_parents (dest, parent\_mode, FALSE) != 0)
die\_with\_error ("Can't mkdir parents for %s", op->dest);
}
switch (op->type)
{
case SETUP\_RO\_BIND\_MOUNT:
case SETUP\_DEV\_BIND\_MOUNT:
case SETUP\_BIND\_MOUNT:
if (source\_mode == S\_IFDIR)
{
if (ensure\_dir (dest, 0755) != 0)
die\_with\_error ("Can't mkdir %s", op->dest);
}
else if (ensure\_file (dest, 0444) != 0)
die\_with\_error ("Can't create file at %s", op->dest);
privileged\_op (privileged\_op\_socket,
PRIV\_SEP\_OP\_BIND\_MOUNT,
(op->type == SETUP\_RO\_BIND\_MOUNT ? BIND\_READONLY : 0) |
(op->type == SETUP\_DEV\_BIND\_MOUNT ? BIND\_DEVICES : 0),
0, 0, source, dest);
break;
case SETUP\_REMOUNT\_RO\_NO\_RECURSIVE:
privileged\_op (privileged\_op\_socket,
PRIV\_SEP\_OP\_REMOUNT\_RO\_NO\_RECURSIVE, 0, 0, 0, NULL, dest);
break;
case SETUP\_MOUNT\_PROC:
if (ensure\_dir (dest, 0755) != 0)
die\_with\_error ("Can't mkdir %s", op->dest);
if (unshare\_pid || opt\_pidns\_fd != -1)
{
/\* Our own procfs \*/
privileged\_op (privileged\_op\_socket,
PRIV\_SEP\_OP\_PROC\_MOUNT, 0, 0, 0,
dest, NULL);
}
else
{
/\* Use system procfs, as we share pid namespace anyway \*/
privileged\_op (privileged\_op\_socket,
PRIV\_SEP\_OP\_BIND\_MOUNT, 0, 0, 0,
"oldroot/proc", dest);
}
/\* There are a bunch of weird old subdirs of /proc that could potentially be
problematic (for instance /proc/sysrq-trigger lets you shut down the machine
if you have write access). We should not have access to these as a non-privileged
user, but lets cover them anyway just to make sure \*/
static const char \* const cover\_proc\_dirs[] = { "sys", "sysrq-trigger", "irq", "bus" };
for (i = 0; i < N\_ELEMENTS (cover\_proc\_dirs); i++)
{
cleanup\_free char \*subdir = strconcat3 (dest, "/", cover\_proc\_dirs[i]);
if (access (subdir, W\_OK) < 0)
{
/\* The file is already read-only or doesn't exist. \*/
if (errno == EACCES || errno == ENOENT || errno == EROFS)
continue;
die\_with\_error ("Can't access %s", subdir);
}
privileged\_op (privileged\_op\_socket,
PRIV\_SEP\_OP\_BIND\_MOUNT, BIND\_READONLY, 0, 0,
subdir, subdir);
}
break;
case SETUP\_MOUNT\_DEV:
if (ensure\_dir (dest, 0755) != 0)
die\_with\_error ("Can't mkdir %s", op->dest);
privileged\_op (privileged\_op\_socket,
PRIV\_SEP\_OP\_TMPFS\_MOUNT, 0, 0755, 0,
dest, NULL);
static const char \*const devnodes[] = { "null", "zero", "full", "random", "urandom", "tty" };
for (i = 0; i < N\_ELEMENTS (devnodes); i++)
{
cleanup\_free char \*node\_dest = strconcat3 (dest, "/", devnodes[i]);
cleanup\_free char \*node\_src = strconcat ("/oldroot/dev/", devnodes[i]);
if (create\_file (node\_dest, 0444, NULL) != 0)
die\_with\_error ("Can't create file %s/%s", op->dest, devnodes[i]);
privileged\_op (privileged\_op\_socket,
PRIV\_SEP\_OP\_BIND\_MOUNT, BIND\_DEVICES, 0, 0,
node\_src, node\_dest);
}
static const char \*const stdionodes[] = { "stdin", "stdout", "stderr" };
for (i = 0; i < N\_ELEMENTS (stdionodes); i++)
{
cleanup\_free char \*target = xasprintf ("/proc/self/fd/%d", i);
cleanup\_free char \*node\_dest = strconcat3 (dest, "/", stdionodes[i]);
if (symlink (target, node\_dest) < 0)
die\_with\_error ("Can't create symlink %s/%s", op->dest, stdionodes[i]);
}
/\* /dev/fd and /dev/core - legacy, but both nspawn and docker do these \*/
{ cleanup\_free char \*dev\_fd = strconcat (dest, "/fd");
if (symlink ("/proc/self/fd", dev\_fd) < 0)
die\_with\_error ("Can't create symlink %s", dev\_fd);
}
{ cleanup\_free char \*dev\_core = strconcat (dest, "/core");
if (symlink ("/proc/kcore", dev\_core) < 0)
die\_with\_error ("Can't create symlink %s", dev\_core);
}
{
cleanup\_free char \*pts = strconcat (dest, "/pts");
cleanup\_free char \*ptmx = strconcat (dest, "/ptmx");
cleanup\_free char \*shm = strconcat (dest, "/shm");
if (mkdir (shm, 0755) == -1)
die\_with\_error ("Can't create %s/shm", op->dest);
if (mkdir (pts, 0755) == -1)
die\_with\_error ("Can't create %s/devpts", op->dest);
privileged\_op (privileged\_op\_socket,
PRIV\_SEP\_OP\_DEVPTS\_MOUNT, 0, 0, 0, pts, NULL);
if (symlink ("pts/ptmx", ptmx) != 0)
die\_with\_error ("Can't make symlink at %s/ptmx", op->dest);
}
/\* If stdout is a tty, that means the sandbox can write to the
outside-sandbox tty. In that case we also create a /dev/console
that points to this tty device. This should not cause any more
access than we already have, and it makes ttyname() work in the
sandbox. \*/
if (host\_tty\_dev != NULL && \*host\_tty\_dev != 0)
{
cleanup\_free char \*src\_tty\_dev = strconcat ("/oldroot", host\_tty\_dev);
cleanup\_free char \*dest\_console = strconcat (dest, "/console");
if (create\_file (dest\_console, 0444, NULL) != 0)
die\_with\_error ("creating %s/console", op->dest);
privileged\_op (privileged\_op\_socket,
PRIV\_SEP\_OP\_BIND\_MOUNT, BIND\_DEVICES, 0, 0,
src\_tty\_dev, dest\_console);
}
break;
case SETUP\_MOUNT\_TMPFS:
assert (dest != NULL);
assert (op->perms >= 0);
assert (op->perms <= 07777);
if (ensure\_dir (dest, 0755) != 0)
die\_with\_error ("Can't mkdir %s", op->dest);
privileged\_op (privileged\_op\_socket,
PRIV\_SEP\_OP\_TMPFS\_MOUNT, 0, op->perms, op->size,
dest, NULL);
break;
case SETUP\_MOUNT\_MQUEUE:
if (ensure\_dir (dest, 0755) != 0)
die\_with\_error ("Can't mkdir %s", op->dest);
privileged\_op (privileged\_op\_socket,
PRIV\_SEP\_OP\_MQUEUE\_MOUNT, 0, 0, 0,
dest, NULL);
break;
case SETUP\_MAKE\_DIR:
assert (dest != NULL);
assert (op->perms >= 0);
assert (op->perms <= 07777);
if (ensure\_dir (dest, op->perms) != 0)
die\_with\_error ("Can't mkdir %s", op->dest);
break;
case SETUP\_CHMOD:
assert (op->dest != NULL);
/\* We used NO\_CREATE\_DEST so we have to use get\_newroot\_path()
\* explicitly \*/
assert (dest == NULL);
dest = get\_newroot\_path (op->dest);
assert (dest != NULL);
assert (op->perms >= 0);
assert (op->perms <= 07777);
if (chmod (dest, op->perms) != 0)
die\_with\_error ("Can't chmod %#o %s", op->perms, op->dest);
break;
case SETUP\_MAKE\_FILE:
{
cleanup\_fd int dest\_fd = -1;
assert (dest != NULL);
assert (op->perms >= 0);
assert (op->perms <= 07777);
dest\_fd = creat (dest, op->perms);
if (dest\_fd == -1)
die\_with\_error ("Can't create file %s", op->dest);
if (copy\_file\_data (op->fd, dest\_fd) != 0)
die\_with\_error ("Can't write data to file %s", op->dest);
close (op->fd);
op->fd = -1;
}
break;
case SETUP\_MAKE\_BIND\_FILE:
case SETUP\_MAKE\_RO\_BIND\_FILE:
{
cleanup\_fd int dest\_fd = -1;
char tempfile[] = "/bindfileXXXXXX";
assert (dest != NULL);
assert (op->perms >= 0);
assert (op->perms <= 07777);
dest\_fd = mkstemp (tempfile);
if (dest\_fd == -1)
die\_with\_error ("Can't create tmpfile for %s", op->dest);
if (fchmod (dest\_fd, op->perms) != 0)
die\_with\_error ("Can't set mode %#o on file to be used for %s",
op->perms, op->dest);
if (copy\_file\_data (op->fd, dest\_fd) != 0)
die\_with\_error ("Can't write data to file %s", op->dest);
close (op->fd);
op->fd = -1;
assert (dest != NULL);
if (ensure\_file (dest, 0444) != 0)
die\_with\_error ("Can't create file at %s", op->dest);
privileged\_op (privileged\_op\_socket,
PRIV\_SEP\_OP\_BIND\_MOUNT,
(op->type == SETUP\_MAKE\_RO\_BIND\_FILE ? BIND\_READONLY : 0),
0, 0, tempfile, dest);
/\* Remove the file so we're sure the app can't get to it in any other way.
Its outside the container chroot, so it shouldn't be possible, but lets
make it really sure. \*/
unlink (tempfile);
}
break;
case SETUP\_MAKE\_SYMLINK:
assert (op->source != NULL); /\* guaranteed by the constructor \*/
if (symlink (op->source, dest) != 0)
die\_with\_error ("Can't make symlink at %s", op->dest);
break;
case SETUP\_SET\_HOSTNAME:
assert (op->dest != NULL); /\* guaranteed by the constructor \*/
privileged\_op (privileged\_op\_socket,
PRIV\_SEP\_OP\_SET\_HOSTNAME, 0, 0, 0,
op->dest, NULL);
break;
default:
die ("Unexpected type %d", op->type);
}
}
privileged\_op (privileged\_op\_socket,
PRIV\_SEP\_OP\_DONE, 0, 0, 0, NULL, NULL);
}
/\* Do not leak file descriptors already used by setup\_newroot () \*/
static void
close\_ops\_fd (void)
{
SetupOp \*op;
for (op = ops; op != NULL; op = op->next)
{
if (op->fd != -1)
{
(void) close (op->fd);
op->fd = -1;
}
}
}
/\* We need to resolve relative symlinks in the sandbox before we
chroot so that absolute symlinks are handled correctly. We also
need to do this after we've switched to the real uid so that
e.g. paths on fuse mounts work \*/
static void
resolve\_symlinks\_in\_ops (void)
{
SetupOp \*op;
for (op = ops; op != NULL; op = op->next)
{
const char \*old\_source;
switch (op->type)
{
case SETUP\_RO\_BIND\_MOUNT:
case SETUP\_DEV\_BIND\_MOUNT:
case SETUP\_BIND\_MOUNT:
old\_source = op->source;
op->source = realpath (old\_source, NULL);
if (op->source == NULL)
{
if (op->flags & ALLOW\_NOTEXIST && errno == ENOENT)
op->source = old\_source;
else
die\_with\_error("Can't find source path %s", old\_source);
}
break;
case SETUP\_MOUNT\_PROC:
case SETUP\_MOUNT\_DEV:
case SETUP\_MOUNT\_TMPFS:
case SETUP\_MOUNT\_MQUEUE:
case SETUP\_MAKE\_DIR:
case SETUP\_MAKE\_FILE:
case SETUP\_MAKE\_BIND\_FILE:
case SETUP\_MAKE\_RO\_BIND\_FILE:
case SETUP\_MAKE\_SYMLINK:
case SETUP\_REMOUNT\_RO\_NO\_RECURSIVE:
case SETUP\_SET\_HOSTNAME:
case SETUP\_CHMOD:
default:
break;
}
}
}
static const char \*
resolve\_string\_offset (void \*buffer,
size\_t buffer\_size,
uint32\_t offset)
{
if (offset == 0)
return NULL;
if (offset > buffer\_size)
die ("Invalid string offset %d (buffer size %zd)", offset, buffer\_size);
return (const char \*) buffer + offset;
}
static uint32\_t
read\_priv\_sec\_op (int read\_socket,
void \*buffer,
size\_t buffer\_size,
uint32\_t \*flags,
uint32\_t \*perms,
size\_t \*size\_arg,
const char \*\*arg1,
const char \*\*arg2)
{
const PrivSepOp \*op = (const PrivSepOp \*) buffer;
ssize\_t rec\_len;
do
rec\_len = read (read\_socket, buffer, buffer\_size - 1);
while (rec\_len == -1 && errno == EINTR);
if (rec\_len < 0)
die\_with\_error ("Can't read from unprivileged helper");
if (rec\_len == 0)
exit (1); /\* Privileged helper died and printed error, so exit silently \*/
if (rec\_len < sizeof (PrivSepOp))
die ("Invalid size %zd from unprivileged helper", rec\_len);
/\* Guarantee zero termination of any strings \*/
((char \*) buffer)[rec\_len] = 0;
\*flags = op->flags;
\*perms = op->perms;
\*size\_arg = op->size\_arg;
\*arg1 = resolve\_string\_offset (buffer, rec\_len, op->arg1\_offset);
\*arg2 = resolve\_string\_offset (buffer, rec\_len, op->arg2\_offset);
return op->op;
}
static void \_\_attribute\_\_ ((noreturn))
print\_version\_and\_exit (void)
{
printf ("%s\n", PACKAGE\_STRING);
exit (0);
}
static int
is\_modifier\_option (const char \*option)
{
return strcmp (option, "--perms") == 0
|| strcmp(option, "--size") == 0;
}
static void
warn\_only\_last\_option (const char \*name)
{
warn ("Only the last %s option will take effect", name);
}
static void
parse\_args\_recurse (int \*argcp,
const char \*\*\*argvp,
bool in\_file,
int \*total\_parsed\_argc\_p)
{
SetupOp \*op;
int argc = \*argcp;
const char \*\*argv = \*argvp;
/\* I can't imagine a case where someone wants more than this.
\* If you do...you should be able to pass multiple files
\* via a single tmpfs and linking them there, etc.
\*
\* We're adding this hardening due to precedent from
\* http://googleprojectzero.blogspot.com/2014/08/the-poisoned-nul-byte-2014-edition.html
\*
\* I picked 9000 because the Internet told me to and it was hard to
\* resist.
\*/
static const uint32\_t MAX\_ARGS = 9000;
if (\*total\_parsed\_argc\_p > MAX\_ARGS)
die ("Exceeded maximum number of arguments %u", MAX\_ARGS);
while (argc > 0)
{
const char \*arg = argv[0];
if (strcmp (arg, "--help") == 0)
{
usage (EXIT\_SUCCESS, stdout);
}
else if (strcmp (arg, "--version") == 0)
{
print\_version\_and\_exit ();
}
else if (strcmp (arg, "--args") == 0)
{
int the\_fd;
char \*endptr;
const char \*p, \*data\_end;
size\_t data\_len;
cleanup\_free const char \*\*data\_argv = NULL;
const char \*\*data\_argv\_copy;
int data\_argc;
int i;
if (in\_file)
die ("--args not supported in arguments file");
if (argc < 2)
die ("--args takes an argument");
the\_fd = strtol (argv[1], &endptr, 10);
if (argv[1][0] == 0 || endptr[0] != 0 || the\_fd < 0)
die ("Invalid fd: %s", argv[1]);
/\* opt\_args\_data is essentially a recursive argv array, which we must
\* keep allocated until exit time, since its argv entries get used
\* by the other cases in parse\_args\_recurse() when we recurse. \*/
opt\_args\_data = load\_file\_data (the\_fd, &data\_len);
if (opt\_args\_data == NULL)
die\_with\_error ("Can't read --args data");
(void) close (the\_fd);
data\_end = opt\_args\_data + data\_len;
data\_argc = 0;
p = opt\_args\_data;
while (p != NULL && p < data\_end)
{
data\_argc++;
(\*total\_parsed\_argc\_p)++;
if (\*total\_parsed\_argc\_p > MAX\_ARGS)
die ("Exceeded maximum number of arguments %u", MAX\_ARGS);
p = memchr (p, 0, data\_end - p);
if (p != NULL)
p++;
}
data\_argv = xcalloc (sizeof (char \*) \* (data\_argc + 1));
i = 0;
p = opt\_args\_data;
while (p != NULL && p < data\_end)
{
/\* Note: load\_file\_data always adds a nul terminator, so this is safe
\* even for the last string. \*/
data\_argv[i++] = p;
p = memchr (p, 0, data\_end - p);
if (p != NULL)
p++;
}
data\_argv\_copy = data\_argv; /\* Don't change data\_argv, we need to free it \*/
parse\_args\_recurse (&data\_argc, &data\_argv\_copy, TRUE, total\_parsed\_argc\_p);
argv += 1;
argc -= 1;
}
else if (strcmp (arg, "--unshare-all") == 0)
{
/\* Keep this in order with the older (legacy) --unshare arguments,
\* we use the --try variants of user and cgroup, since we want
\* to support systems/kernels without support for those.
\*/
opt\_unshare\_user\_try = opt\_unshare\_ipc = opt\_unshare\_pid =
opt\_unshare\_uts = opt\_unshare\_cgroup\_try =
opt\_unshare\_net = TRUE;
}
/\* Begin here the older individual --unshare variants \*/
else if (strcmp (arg, "--unshare-user") == 0)
{
opt\_unshare\_user = TRUE;
}
else if (strcmp (arg, "--unshare-user-try") == 0)
{
opt\_unshare\_user\_try = TRUE;
}
else if (strcmp (arg, "--unshare-ipc") == 0)
{
opt\_unshare\_ipc = TRUE;
}
else if (strcmp (arg, "--unshare-pid") == 0)
{
opt\_unshare\_pid = TRUE;
}
else if (strcmp (arg, "--unshare-net") == 0)
{
opt\_unshare\_net = TRUE;
}
else if (strcmp (arg, "--unshare-uts") == 0)
{
opt\_unshare\_uts = TRUE;
}
else if (strcmp (arg, "--unshare-cgroup") == 0)
{
opt\_unshare\_cgroup = TRUE;
}
else if (strcmp (arg, "--unshare-cgroup-try") == 0)
{
opt\_unshare\_cgroup\_try = TRUE;
}
/\* Begin here the newer --share variants \*/
else if (strcmp (arg, "--share-net") == 0)
{
opt\_unshare\_net = FALSE;
}
/\* End --share variants, other arguments begin \*/
else if (strcmp (arg, "--chdir") == 0)
{
if (argc < 2)
die ("--chdir takes one argument");
if (opt\_chdir\_path != NULL)
warn\_only\_last\_option ("--chdir");
opt\_chdir\_path = argv[1];
argv++;
argc--;
}
else if (strcmp (arg, "--disable-userns") == 0)
{
opt\_disable\_userns = TRUE;
}
else if (strcmp (arg, "--assert-userns-disabled") == 0)
{
opt\_assert\_userns\_disabled = TRUE;
}
else if (strcmp (arg, "--remount-ro") == 0)
{
if (argc < 2)
die ("--remount-ro takes one argument");
op = setup\_op\_new (SETUP\_REMOUNT\_RO\_NO\_RECURSIVE);
op->dest = argv[1];
argv++;
argc--;
}
else if (strcmp(arg, "--bind") == 0 ||
strcmp(arg, "--bind-try") == 0)
{
if (argc < 3)
die ("%s takes two arguments", arg);
op = setup\_op\_new (SETUP\_BIND\_MOUNT);
op->source = argv[1];
op->dest = argv[2];
if (strcmp(arg, "--bind-try") == 0)
op->flags = ALLOW\_NOTEXIST;
argv += 2;
argc -= 2;
}
else if (strcmp(arg, "--ro-bind") == 0 ||
strcmp(arg, "--ro-bind-try") == 0)
{
if (argc < 3)
die ("%s takes two arguments", arg);
op = setup\_op\_new (SETUP\_RO\_BIND\_MOUNT);
op->source = argv[1];
op->dest = argv[2];
if (strcmp(arg, "--ro-bind-try") == 0)
op->flags = ALLOW\_NOTEXIST;
argv += 2;
argc -= 2;
}
else if (strcmp (arg, "--dev-bind") == 0 ||
strcmp (arg, "--dev-bind-try") == 0)
{
if (argc < 3)
die ("%s takes two arguments", arg);
op = setup\_op\_new (SETUP\_DEV\_BIND\_MOUNT);
op->source = argv[1];
op->dest = argv[2];
if (strcmp(arg, "--dev-bind-try") == 0)
op->flags = ALLOW\_NOTEXIST;
argv += 2;
argc -= 2;
}
else if (strcmp (arg, "--proc") == 0)
{
if (argc < 2)
die ("--proc takes an argument");
op = setup\_op\_new (SETUP\_MOUNT\_PROC);
op->dest = argv[1];
argv += 1;
argc -= 1;
}
else if (strcmp (arg, "--exec-label") == 0)
{
if (argc < 2)
die ("--exec-label takes an argument");
if (opt\_exec\_label != NULL)
warn\_only\_last\_option ("--exec-label");
opt\_exec\_label = argv[1];
die\_unless\_label\_valid (opt\_exec\_label);
argv += 1;
argc -= 1;
}
else if (strcmp (arg, "--file-label") == 0)
{
if (argc < 2)
die ("--file-label takes an argument");
if (opt\_file\_label != NULL)
warn\_only\_last\_option ("--file-label");
opt\_file\_label = argv[1];
die\_unless\_label\_valid (opt\_file\_label);
if (label\_create\_file (opt\_file\_label))
die\_with\_error ("--file-label setup failed");
argv += 1;
argc -= 1;
}
else if (strcmp (arg, "--dev") == 0)
{
if (argc < 2)
die ("--dev takes an argument");
op = setup\_op\_new (SETUP\_MOUNT\_DEV);
op->dest = argv[1];
opt\_needs\_devpts = TRUE;
argv += 1;
argc -= 1;
}
else if (strcmp (arg, "--tmpfs") == 0)
{
if (argc < 2)
die ("--tmpfs takes an argument");
op = setup\_op\_new (SETUP\_MOUNT\_TMPFS);
op->dest = argv[1];
/\* We historically hard-coded the mode of a tmpfs as 0755. \*/
if (next\_perms >= 0)
op->perms = next\_perms;
else
op->perms = 0755;
next\_perms = -1;
/\* If the option is unset, next\_size\_arg is zero, which results in
\* the default tmpfs size. This is exactly what we want. \*/
op->size = next\_size\_arg;
next\_size\_arg = 0;
argv += 1;
argc -= 1;
}
else if (strcmp (arg, "--mqueue") == 0)
{
if (argc < 2)
die ("--mqueue takes an argument");
op = setup\_op\_new (SETUP\_MOUNT\_MQUEUE);
op->dest = argv[1];
argv += 1;
argc -= 1;
}
else if (strcmp (arg, "--dir") == 0)
{
if (argc < 2)
die ("--dir takes an argument");
op = setup\_op\_new (SETUP\_MAKE\_DIR);
op->dest = argv[1];
/\* We historically hard-coded the mode of a --dir as 0755. \*/
if (next\_perms >= 0)
op->perms = next\_perms;
else
op->perms = 0755;
next\_perms = -1;
argv += 1;
argc -= 1;
}
else if (strcmp (arg, "--file") == 0)
{
int file\_fd;
char \*endptr;
if (argc < 3)
die ("--file takes two arguments");
file\_fd = strtol (argv[1], &endptr, 10);
if (argv[1][0] == 0 || endptr[0] != 0 || file\_fd < 0)
die ("Invalid fd: %s", argv[1]);
op = setup\_op\_new (SETUP\_MAKE\_FILE);
op->fd = file\_fd;
op->dest = argv[2];
/\* We historically hard-coded the mode of a --file as 0666. \*/
if (next\_perms >= 0)
op->perms = next\_perms;
else
op->perms = 0666;
next\_perms = -1;
argv += 2;
argc -= 2;
}
else if (strcmp (arg, "--bind-data") == 0)
{
int file\_fd;
char \*endptr;
if (argc < 3)
die ("--bind-data takes two arguments");
file\_fd = strtol (argv[1], &endptr, 10);
if (argv[1][0] == 0 || endptr[0] != 0 || file\_fd < 0)
die ("Invalid fd: %s", argv[1]);
op = setup\_op\_new (SETUP\_MAKE\_BIND\_FILE);
op->fd = file\_fd;
op->dest = argv[2];
/\* This is consistent with previous bubblewrap behaviour:
\* before implementing --perms, we took the permissions
\* given to us by mkstemp(), which are documented to be 0600. \*/
if (next\_perms >= 0)
op->perms = next\_perms;
else
op->perms = 0600;
next\_perms = -1;
argv += 2;
argc -= 2;
}
else if (strcmp (arg, "--ro-bind-data") == 0)
{
int file\_fd;
char \*endptr;
if (argc < 3)
die ("--ro-bind-data takes two arguments");
file\_fd = strtol (argv[1], &endptr, 10);
if (argv[1][0] == 0 || endptr[0] != 0 || file\_fd < 0)
die ("Invalid fd: %s", argv[1]);
op = setup\_op\_new (SETUP\_MAKE\_RO\_BIND\_FILE);
op->fd = file\_fd;
op->dest = argv[2];
/\* This is consistent with previous bubblewrap behaviour:
\* before implementing --perms, we took the permissions
\* given to us by mkstemp(), which are documented to be 0600. \*/
if (next\_perms >= 0)
op->perms = next\_perms;
else
op->perms = 0600;
next\_perms = -1;
argv += 2;
argc -= 2;
}
else if (strcmp (arg, "--symlink") == 0)
{
if (argc < 3)
die ("--symlink takes two arguments");
op = setup\_op\_new (SETUP\_MAKE\_SYMLINK);
op->source = argv[1];
op->dest = argv[2];
argv += 2;
argc -= 2;
}
else if (strcmp (arg, "--lock-file") == 0)
{
if (argc < 2)
die ("--lock-file takes an argument");
(void) lock\_file\_new (argv[1]);
argv += 1;
argc -= 1;
}
else if (strcmp (arg, "--sync-fd") == 0)
{
int the\_fd;
char \*endptr;
if (argc < 2)
die ("--sync-fd takes an argument");
if (opt\_sync\_fd != -1)
warn\_only\_last\_option ("--sync-fd");
the\_fd = strtol (argv[1], &endptr, 10);
if (argv[1][0] == 0 || endptr[0] != 0 || the\_fd < 0)
die ("Invalid fd: %s", argv[1]);
opt\_sync\_fd = the\_fd;
argv += 1;
argc -= 1;
}
else if (strcmp (arg, "--block-fd") == 0)
{
int the\_fd;
char \*endptr;
if (argc < 2)
die ("--block-fd takes an argument");
if (opt\_block\_fd != -1)
warn\_only\_last\_option ("--block-fd");
the\_fd = strtol (argv[1], &endptr, 10);
if (argv[1][0] == 0 || endptr[0] != 0 || the\_fd < 0)
die ("Invalid fd: %s", argv[1]);
opt\_block\_fd = the\_fd;
argv += 1;
argc -= 1;
}
else if (strcmp (arg, "--userns-block-fd") == 0)
{
int the\_fd;
char \*endptr;
if (argc < 2)
die ("--userns-block-fd takes an argument");
if (opt\_userns\_block\_fd != -1)
warn\_only\_last\_option ("--userns-block-fd");
the\_fd = strtol (argv[1], &endptr, 10);
if (argv[1][0] == 0 || endptr[0] != 0 || the\_fd < 0)
die ("Invalid fd: %s", argv[1]);
opt\_userns\_block\_fd = the\_fd;
argv += 1;
argc -= 1;
}
else if (strcmp (arg, "--info-fd") == 0)
{
int the\_fd;
char \*endptr;
if (argc < 2)
die ("--info-fd takes an argument");
if (opt\_info\_fd != -1)
warn\_only\_last\_option ("--info-fd");
the\_fd = strtol (argv[1], &endptr, 10);
if (argv[1][0] == 0 || endptr[0] != 0 || the\_fd < 0)
die ("Invalid fd: %s", argv[1]);
opt\_info\_fd = the\_fd;
argv += 1;
argc -= 1;
}
else if (strcmp (arg, "--json-status-fd") == 0)
{
int the\_fd;
char \*endptr;
if (argc < 2)
die ("--json-status-fd takes an argument");
if (opt\_json\_status\_fd != -1)
warn\_only\_last\_option ("--json-status-fd");
the\_fd = strtol (argv[1], &endptr, 10);
if (argv[1][0] == 0 || endptr[0] != 0 || the\_fd < 0)
die ("Invalid fd: %s", argv[1]);
opt\_json\_status\_fd = the\_fd;
argv += 1;
argc -= 1;
}
else if (strcmp (arg, "--seccomp") == 0)
{
int the\_fd;
char \*endptr;
if (argc < 2)
die ("--seccomp takes an argument");
if (seccomp\_programs != NULL)
die ("--seccomp cannot be combined with --add-seccomp-fd");
if (opt\_seccomp\_fd != -1)
warn\_only\_last\_option ("--seccomp");
the\_fd = strtol (argv[1], &endptr, 10);
if (argv[1][0] == 0 || endptr[0] != 0 || the\_fd < 0)
die ("Invalid fd: %s", argv[1]);
opt\_seccomp\_fd = the\_fd;
argv += 1;
argc -= 1;
}
else if (strcmp (arg, "--add-seccomp-fd") == 0)
{
int the\_fd;
char \*endptr;
if (argc < 2)
die ("--add-seccomp-fd takes an argument");
if (opt\_seccomp\_fd != -1)
die ("--add-seccomp-fd cannot be combined with --seccomp");
the\_fd = strtol (argv[1], &endptr, 10);
if (argv[1][0] == 0 || endptr[0] != 0 || the\_fd < 0)
die ("Invalid fd: %s", argv[1]);
/\* takes ownership of fd \*/
seccomp\_program\_new (&the\_fd);
argv += 1;
argc -= 1;
}
else if (strcmp (arg, "--userns") == 0)
{
int the\_fd;
char \*endptr;
if (argc < 2)
die ("--userns takes an argument");
if (opt\_userns\_fd != -1)
warn\_only\_last\_option ("--userns");
the\_fd = strtol (argv[1], &endptr, 10);
if (argv[1][0] == 0 || endptr[0] != 0 || the\_fd < 0)
die ("Invalid fd: %s", argv[1]);
opt\_userns\_fd = the\_fd;
argv += 1;
argc -= 1;
}
else if (strcmp (arg, "--userns2") == 0)
{
int the\_fd;
char \*endptr;
if (argc < 2)
die ("--userns2 takes an argument");
if (opt\_userns2\_fd != -1)
warn\_only\_last\_option ("--userns2");
the\_fd = strtol (argv[1], &endptr, 10);
if (argv[1][0] == 0 || endptr[0] != 0 || the\_fd < 0)
die ("Invalid fd: %s", argv[1]);
opt\_userns2\_fd = the\_fd;
argv += 1;
argc -= 1;
}
else if (strcmp (arg, "--pidns") == 0)
{
int the\_fd;
char \*endptr;
if (argc < 2)
die ("--pidns takes an argument");
if (opt\_pidns\_fd != -1)
warn\_only\_last\_option ("--pidns");
the\_fd = strtol (argv[1], &endptr, 10);
if (argv[1][0] == 0 || endptr[0] != 0 || the\_fd < 0)
die ("Invalid fd: %s", argv[1]);
opt\_pidns\_fd = the\_fd;
argv += 1;
argc -= 1;
}
else if (strcmp (arg, "--clearenv") == 0)
{
xclearenv ();
}
else if (strcmp (arg, "--setenv") == 0)
{
if (argc < 3)
die ("--setenv takes two arguments");
xsetenv (argv[1], argv[2], 1);
argv += 2;
argc -= 2;
}
else if (strcmp (arg, "--unsetenv") == 0)
{
if (argc < 2)
die ("--unsetenv takes an argument");
xunsetenv (argv[1]);
argv += 1;
argc -= 1;
}
else if (strcmp (arg, "--uid") == 0)
{
int the\_uid;
char \*endptr;
if (argc < 2)
die ("--uid takes an argument");
if (opt\_sandbox\_uid != -1)
warn\_only\_last\_option ("--uid");
the\_uid = strtol (argv[1], &endptr, 10);
if (argv[1][0] == 0 || endptr[0] != 0 || the\_uid < 0)
die ("Invalid uid: %s", argv[1]);
opt\_sandbox\_uid = the\_uid;
argv += 1;
argc -= 1;
}
else if (strcmp (arg, "--gid") == 0)
{
int the\_gid;
char \*endptr;
if (argc < 2)
die ("--gid takes an argument");
if (opt\_sandbox\_gid != -1)
warn\_only\_last\_option ("--gid");
the\_gid = strtol (argv[1], &endptr, 10);
if (argv[1][0] == 0 || endptr[0] != 0 || the\_gid < 0)
die ("Invalid gid: %s", argv[1]);
opt\_sandbox\_gid = the\_gid;
argv += 1;
argc -= 1;
}
else if (strcmp (arg, "--hostname") == 0)
{
if (argc < 2)
die ("--hostname takes an argument");
if (opt\_sandbox\_hostname != NULL)
warn\_only\_last\_option ("--hostname");
op = setup\_op\_new (SETUP\_SET\_HOSTNAME);
op->dest = argv[1];
op->flags = NO\_CREATE\_DEST;
opt\_sandbox\_hostname = argv[1];
argv += 1;
argc -= 1;
}
else if (strcmp (arg, "--new-session") == 0)
{
opt\_new\_session = TRUE;
}
else if (strcmp (arg, "--die-with-parent") == 0)
{
opt\_die\_with\_parent = TRUE;
}
else if (strcmp (arg, "--as-pid-1") == 0)
{
opt\_as\_pid\_1 = TRUE;
}
else if (strcmp (arg, "--cap-add") == 0)
{
cap\_value\_t cap;
if (argc < 2)
die ("--cap-add takes an argument");
opt\_cap\_add\_or\_drop\_used = TRUE;
if (strcasecmp (argv[1], "ALL") == 0)
{
requested\_caps[0] = requested\_caps[1] = 0xFFFFFFFF;
}
else
{
if (cap\_from\_name (argv[1], &cap) < 0)
die ("unknown cap: %s", argv[1]);
if (cap < 32)
requested\_caps[0] |= CAP\_TO\_MASK\_0 (cap);
else
requested\_caps[1] |= CAP\_TO\_MASK\_1 (cap - 32);
}
argv += 1;
argc -= 1;
}
else if (strcmp (arg, "--cap-drop") == 0)
{
cap\_value\_t cap;
if (argc < 2)
die ("--cap-drop takes an argument");
opt\_cap\_add\_or\_drop\_used = TRUE;
if (strcasecmp (argv[1], "ALL") == 0)
{
requested\_caps[0] = requested\_caps[1] = 0;
}
else
{
if (cap\_from\_name (argv[1], &cap) < 0)
die ("unknown cap: %s", argv[1]);
if (cap < 32)
requested\_caps[0] &= ~CAP\_TO\_MASK\_0 (cap);
else
requested\_caps[1] &= ~CAP\_TO\_MASK\_1 (cap - 32);
}
argv += 1;
argc -= 1;
}
else if (strcmp (arg, "--perms") == 0)
{
unsigned long perms;
char \*endptr = NULL;
if (argc < 2)
die ("--perms takes an argument");
if (next\_perms != -1)
die ("--perms given twice for the same action");
perms = strtoul (argv[1], &endptr, 8);
if (argv[1][0] == '\0'
|| endptr == NULL
|| \*endptr != '\0'
|| perms > 07777)
die ("--perms takes an octal argument <= 07777");
next\_perms = (int) perms;
argv += 1;
argc -= 1;
}
else if (strcmp (arg, "--size") == 0)
{
unsigned long long size;
char \*endptr = NULL;
if (is\_privileged)
die ("The --size option is not permitted in setuid mode");
if (argc < 2)
die ("--size takes an argument");
if (next\_size\_arg != 0)
die ("--size given twice for the same action");
errno = 0; /\* reset errno so we can detect ERANGE from strtoull \*/
size = strtoull (argv[1], &endptr, 0);
/\* isdigit: Not only check that the first digit is not '\0', but
\* simultaneously guard against negative numbers or preceding
\* spaces. \*/
if (errno != 0 /\* from strtoull \*/
|| !isdigit(argv[1][0])
|| endptr == NULL
|| \*endptr != '\0'
|| size == 0)
die ("--size takes a non-zero number of bytes");
if (size > MAX\_TMPFS\_BYTES)
die ("--size (for tmpfs) is limited to %zu", MAX\_TMPFS\_BYTES);
next\_size\_arg = (size\_t) size;
argv += 1;
argc -= 1;
}
else if (strcmp (arg, "--chmod") == 0)
{
unsigned long perms;
char \*endptr = NULL;
if (argc < 3)
die ("--chmod takes two arguments");
perms = strtoul (argv[1], &endptr, 8);
if (argv[1][0] == '\0'
|| endptr == NULL
|| \*endptr != '\0'
|| perms > 07777)
die ("--chmod takes an octal argument <= 07777");
op = setup\_op\_new (SETUP\_CHMOD);
op->flags = NO\_CREATE\_DEST;
op->perms = (int) perms;
op->dest = argv[2];
argv += 2;
argc -= 2;
}
else if (strcmp (arg, "--") == 0)
{
argv += 1;
argc -= 1;
break;
}
else if (\*arg == '-')
{
die ("Unknown option %s", arg);
}
else
{
break;
}
/\* If --perms was set for the current action but the current action
\* didn't consume the setting, apparently --perms wasn't suitable for
\* this action. \*/
if (!is\_modifier\_option(arg) && next\_perms >= 0)
die ("--perms must be followed by an option that creates a file");
/\* Similarly for --size. \*/
if (!is\_modifier\_option(arg) && next\_size\_arg != 0)
die ("--size must be followed by --tmpfs");
argv++;
argc--;
}
\*argcp = argc;
\*argvp = argv;
}
static void
parse\_args (int \*argcp,
const char \*\*\*argvp)
{
int total\_parsed\_argc = \*argcp;
parse\_args\_recurse (argcp, argvp, FALSE, &total\_parsed\_argc);
}
static void
read\_overflowids (void)
{
cleanup\_free char \*uid\_data = NULL;
cleanup\_free char \*gid\_data = NULL;
uid\_data = load\_file\_at (AT\_FDCWD, "/proc/sys/kernel/overflowuid");
if (uid\_data == NULL)
die\_with\_error ("Can't read /proc/sys/kernel/overflowuid");
overflow\_uid = strtol (uid\_data, NULL, 10);
if (overflow\_uid == 0)
die ("Can't parse /proc/sys/kernel/overflowuid");
gid\_data = load\_file\_at (AT\_FDCWD, "/proc/sys/kernel/overflowgid");
if (gid\_data == NULL)
die\_with\_error ("Can't read /proc/sys/kernel/overflowgid");
overflow\_gid = strtol (gid\_data, NULL, 10);
if (overflow\_gid == 0)
die ("Can't parse /proc/sys/kernel/overflowgid");
}
static void
namespace\_ids\_read (pid\_t pid)
{
cleanup\_free char \*dir = NULL;
cleanup\_fd int ns\_fd = -1;
NsInfo \*info;
dir = xasprintf ("%d/ns", pid);
ns\_fd = openat (proc\_fd, dir, O\_PATH);
if (ns\_fd < 0)
die\_with\_error ("open /proc/%s/ns failed", dir);
for (info = ns\_infos; info->name; info++)
{
bool \*do\_unshare = info->do\_unshare;
struct stat st;
int r;
/\* if we don't unshare this ns, ignore it \*/
if (do\_unshare && \*do\_unshare == FALSE)
continue;
r = fstatat (ns\_fd, info->name, &st, 0);
/\* if we can't get the information, ignore it \*/
if (r != 0)
continue;
info->id = st.st\_ino;
}
}
static void
namespace\_ids\_write (int fd,
bool in\_json)
{
NsInfo \*info;
for (info = ns\_infos; info->name; info++)
{
cleanup\_free char \*output = NULL;
const char \*indent;
uintmax\_t nsid;
nsid = (uintmax\_t) info->id;
/\* if we don't have the information, we don't write it \*/
if (nsid == 0)
continue;
indent = in\_json ? " " : "\n ";
output = xasprintf (",%s\"%s-namespace\": %ju",
indent, info->name, nsid);
dump\_info (fd, output, TRUE);
}
}
int
main (int argc,
char \*\*argv)
{
mode\_t old\_umask;
const char \*base\_path = NULL;
int clone\_flags;
char \*old\_cwd = NULL;
pid\_t pid;
int event\_fd = -1;
int child\_wait\_fd = -1;
int setup\_finished\_pipe[] = {-1, -1};
const char \*new\_cwd;
uid\_t ns\_uid;
gid\_t ns\_gid;
struct stat sbuf;
uint64\_t val;
int res UNUSED;
cleanup\_free char \*args\_data UNUSED = NULL;
int intermediate\_pids\_sockets[2] = {-1, -1};
/\* Handle --version early on before we try to acquire/drop
\* any capabilities so it works in a build environment;
\* right now flatpak's build runs bubblewrap --version.
\* https://github.com/projectatomic/bubblewrap/issues/185
\*/
if (argc == 2 && (strcmp (argv[1], "--version") == 0))
print\_version\_and\_exit ();
real\_uid = getuid ();
real\_gid = getgid ();
/\* Get the (optional) privileges we need \*/
acquire\_privs ();
/\* Never gain any more privs during exec \*/
if (prctl (PR\_SET\_NO\_NEW\_PRIVS, 1, 0, 0, 0) < 0)
die\_with\_error ("prctl(PR\_SET\_NO\_NEW\_PRIVS) failed");
/\* The initial code is run with high permissions
(i.e. CAP\_SYS\_ADMIN), so take lots of care. \*/
read\_overflowids ();
argv0 = argv[0];
if (isatty (1))
host\_tty\_dev = ttyname (1);
argv++;
argc--;
if (argc <= 0)
usage (EXIT\_FAILURE, stderr);
parse\_args (&argc, (const char \*\*\*) &argv);
/\* suck the args into a cleanup\_free variable to control their lifecycle \*/
args\_data = opt\_args\_data;
opt\_args\_data = NULL;
if ((requested\_caps[0] || requested\_caps[1]) && is\_privileged)
die ("--cap-add in setuid mode can be used only by root");
if (opt\_userns\_block\_fd != -1 && !opt\_unshare\_user)
die ("--userns-block-fd requires --unshare-user");
if (opt\_userns\_block\_fd != -1 && opt\_info\_fd == -1)
die ("--userns-block-fd requires --info-fd");
if (opt\_userns\_fd != -1 && opt\_unshare\_user)
die ("--userns not compatible --unshare-user");
if (opt\_userns\_fd != -1 && opt\_unshare\_user\_try)
die ("--userns not compatible --unshare-user-try");
if (opt\_disable\_userns && !opt\_unshare\_user)
die ("--disable-userns requires --unshare-user");
if (opt\_disable\_userns && opt\_userns\_block\_fd != -1)
die ("--disable-userns is not compatible with --userns-block-fd");
/\* Technically using setns() is probably safe even in the privileged
\* case, because we got passed in a file descriptor to the
\* namespace, and that can only be gotten if you have ptrace
\* permissions against the target, and then you could do whatever to
\* the namespace anyway.
\*
\* However, for practical reasons this isn't possible to use,
\* because (as described in acquire\_privs()) setuid bwrap causes
\* root to own the namespaces that it creates, so you will not be
\* able to access these namespaces anyway. So, best just not support
\* it anyway.
\*/
if (opt\_userns\_fd != -1 && is\_privileged)
die ("--userns doesn't work in setuid mode");
if (opt\_userns2\_fd != -1 && is\_privileged)
die ("--userns2 doesn't work in setuid mode");
/\* We have to do this if we weren't installed setuid (and we're not
\* root), so let's just DWIM \*/
if (!is\_privileged && getuid () != 0 && opt\_userns\_fd == -1)
opt\_unshare\_user = TRUE;
#ifdef ENABLE\_REQUIRE\_USERNS
/\* In this build option, we require userns. \*/
if (is\_privileged && getuid () != 0 && opt\_userns\_fd == -1)
opt\_unshare\_user = TRUE;
#endif
if (opt\_unshare\_user\_try &&
stat ("/proc/self/ns/user", &sbuf) == 0)
{
bool disabled = FALSE;
/\* RHEL7 has a kernel module parameter that lets you enable user namespaces \*/
if (stat ("/sys/module/user\_namespace/parameters/enable", &sbuf) == 0)
{
cleanup\_free char \*enable = NULL;
enable = load\_file\_at (AT\_FDCWD, "/sys/module/user\_namespace/parameters/enable");
if (enable != NULL && enable[0] == 'N')
disabled = TRUE;
}
/\* Check for max\_user\_namespaces \*/
if (stat ("/proc/sys/user/max\_user\_namespaces", &sbuf) == 0)
{
cleanup\_free char \*max\_user\_ns = NULL;
max\_user\_ns = load\_file\_at (AT\_FDCWD, "/proc/sys/user/max\_user\_namespaces");
if (max\_user\_ns != NULL && strcmp(max\_user\_ns, "0\n") == 0)
disabled = TRUE;
}
/\* Debian lets you disable \*unprivileged\* user namespaces. However this is not
a problem if we're privileged, and if we're not opt\_unshare\_user is TRUE
already, and there is not much we can do, its just a non-working setup. \*/
if (!disabled)
opt\_unshare\_user = TRUE;
}
if (argc <= 0)
usage (EXIT\_FAILURE, stderr);
\_\_debug\_\_ (("Creating root mount point\n"));
if (opt\_sandbox\_uid == -1)
opt\_sandbox\_uid = real\_uid;
if (opt\_sandbox\_gid == -1)
opt\_sandbox\_gid = real\_gid;
if (!opt\_unshare\_user && opt\_userns\_fd == -1 && opt\_sandbox\_uid != real\_uid)
die ("Specifying --uid requires --unshare-user or --userns");
if (!opt\_unshare\_user && opt\_userns\_fd == -1 && opt\_sandbox\_gid != real\_gid)
die ("Specifying --gid requires --unshare-user or --userns");
if (!opt\_unshare\_uts && opt\_sandbox\_hostname != NULL)
die ("Specifying --hostname requires --unshare-uts");
if (opt\_as\_pid\_1 && !opt\_unshare\_pid)
die ("Specifying --as-pid-1 requires --unshare-pid");
if (opt\_as\_pid\_1 && lock\_files != NULL)
die ("Specifying --as-pid-1 and --lock-file is not permitted");
/\* We need to read stuff from proc during the pivot\_root dance, etc.
Lets keep a fd to it open \*/
proc\_fd = open ("/proc", O\_PATH);
if (proc\_fd == -1)
die\_with\_error ("Can't open /proc");
/\* We need \*some\* mountpoint where we can mount the root tmpfs.
\* Because we use pivot\_root, it won't appear to be mounted from
\* the perspective of the sandboxed process, so we can use anywhere
\* that is sure to exist, that is sure to not be a symlink controlled
\* by someone malicious, and that we won't immediately need to
\* access ourselves. \*/
base\_path = "/tmp";
\_\_debug\_\_ (("creating new namespace\n"));
if (opt\_unshare\_pid && !opt\_as\_pid\_1)
{
event\_fd = eventfd (0, EFD\_CLOEXEC | EFD\_NONBLOCK);
if (event\_fd == -1)
die\_with\_error ("eventfd()");
}
/\* We block sigchild here so that we can use signalfd in the monitor. \*/
block\_sigchild ();
clone\_flags = SIGCHLD | CLONE\_NEWNS;
if (opt\_unshare\_user)
clone\_flags |= CLONE\_NEWUSER;
if (opt\_unshare\_pid && opt\_pidns\_fd == -1)
clone\_flags |= CLONE\_NEWPID;
if (opt\_unshare\_net)
clone\_flags |= CLONE\_NEWNET;
if (opt\_unshare\_ipc)
clone\_flags |= CLONE\_NEWIPC;
if (opt\_unshare\_uts)
clone\_flags |= CLONE\_NEWUTS;
if (opt\_unshare\_cgroup)
{
if (stat ("/proc/self/ns/cgroup", &sbuf))
{
if (errno == ENOENT)
die ("Cannot create new cgroup namespace because the kernel does not support it");
else
die\_with\_error ("stat on /proc/self/ns/cgroup failed");
}
clone\_flags |= CLONE\_NEWCGROUP;
}
if (opt\_unshare\_cgroup\_try)
{
opt\_unshare\_cgroup = !stat ("/proc/self/ns/cgroup", &sbuf);
if (opt\_unshare\_cgroup)
clone\_flags |= CLONE\_NEWCGROUP;
}
child\_wait\_fd = eventfd (0, EFD\_CLOEXEC);
if (child\_wait\_fd == -1)
die\_with\_error ("eventfd()");
/\* Track whether pre-exec setup finished if we're reporting process exit \*/
if (opt\_json\_status\_fd != -1)
{
int ret;
ret = pipe2 (setup\_finished\_pipe, O\_CLOEXEC);
if (ret == -1)
die\_with\_error ("pipe2()");
}
/\* Switch to the custom user ns before the clone, gets us privs in that ns (assuming its a child of the current and thus allowed) \*/
if (opt\_userns\_fd > 0 && setns (opt\_userns\_fd, CLONE\_NEWUSER) != 0)
{
if (errno == EINVAL)
die ("Joining the specified user namespace failed, it might not be a descendant of the current user namespace.");
die\_with\_error ("Joining specified user namespace failed");
}
/\* Sometimes we have uninteresting intermediate pids during the setup, set up code to pass the real pid down \*/
if (opt\_pidns\_fd != -1)
{
/\* Mark us as a subreaper, this way we can get exit status from grandchildren \*/
prctl (PR\_SET\_CHILD\_SUBREAPER, 1, 0, 0, 0);
create\_pid\_socketpair (intermediate\_pids\_sockets);
}
pid = raw\_clone (clone\_flags, NULL);
if (pid == -1)
{
if (opt\_unshare\_user)
{
if (errno == EINVAL)
die ("Creating new namespace failed, likely because the kernel does not support user namespaces. bwrap must be installed setuid on such systems.");
else if (errno == EPERM && !is\_privileged)
die ("No permissions to creating new namespace, likely because the kernel does not allow non-privileged user namespaces. On e.g. debian this can be enabled with 'sysctl kernel.unprivileged\_userns\_clone=1'.");
}
if (errno == ENOSPC)
die ("Creating new namespace failed: nesting depth or /proc/sys/user/max\_\*\_namespaces exceeded (ENOSPC)");
die\_with\_error ("Creating new namespace failed");
}
ns\_uid = opt\_sandbox\_uid;
ns\_gid = opt\_sandbox\_gid;
if (pid != 0)
{
/\* Parent, outside sandbox, privileged (initially) \*/
if (intermediate\_pids\_sockets[0] != -1)
{
close (intermediate\_pids\_sockets[1]);
pid = read\_pid\_from\_socket (intermediate\_pids\_sockets[0]);
close (intermediate\_pids\_sockets[0]);
}
/\* Discover namespace ids before we drop privileges \*/
namespace\_ids\_read (pid);
if (is\_privileged && opt\_unshare\_user && opt\_userns\_block\_fd == -1)
{
/\* We're running as euid 0, but the uid we want to map is
\* not 0. This means we're not allowed to write this from
\* the child user namespace, so we do it from the parent.
\*
\* Also, we map uid/gid 0 in the namespace (to overflowuid)
\* if opt\_needs\_devpts is true, because otherwise the mount
\* of devpts fails due to root not being mapped.
\*/
write\_uid\_gid\_map (ns\_uid, real\_uid,
ns\_gid, real\_gid,
pid, TRUE, opt\_needs\_devpts);
}
/\* Initial launched process, wait for pid 1 or exec:ed command to exit \*/
if (opt\_userns2\_fd > 0 && setns (opt\_userns2\_fd, CLONE\_NEWUSER) != 0)
die\_with\_error ("Setting userns2 failed");
/\* We don't need any privileges in the launcher, drop them immediately. \*/
drop\_privs (FALSE, FALSE);
/\* Optionally bind our lifecycle to that of the parent \*/
handle\_die\_with\_parent ();
if (opt\_info\_fd != -1)
{
cleanup\_free char \*output = xasprintf ("{\n \"child-pid\": %i", pid);
dump\_info (opt\_info\_fd, output, TRUE);
namespace\_ids\_write (opt\_info\_fd, FALSE);
dump\_info (opt\_info\_fd, "\n}\n", TRUE);
close (opt\_info\_fd);
}
if (opt\_json\_status\_fd != -1)
{
cleanup\_free char \*output = xasprintf ("{ \"child-pid\": %i", pid);
dump\_info (opt\_json\_status\_fd, output, TRUE);
namespace\_ids\_write (opt\_json\_status\_fd, TRUE);
dump\_info (opt\_json\_status\_fd, " }\n", TRUE);
}
if (opt\_userns\_block\_fd != -1)
{
char b[1];
(void) TEMP\_FAILURE\_RETRY (read (opt\_userns\_block\_fd, b, 1));
close (opt\_userns\_block\_fd);
}
/\* Let child run now that the uid maps are set up \*/
val = 1;
res = write (child\_wait\_fd, &val, 8);
/\* Ignore res, if e.g. the child died and closed child\_wait\_fd we don't want to error out here \*/
close (child\_wait\_fd);
return monitor\_child (event\_fd, pid, setup\_finished\_pipe[0]);
}
if (opt\_pidns\_fd > 0)
{
if (setns (opt\_pidns\_fd, CLONE\_NEWPID) != 0)
die\_with\_error ("Setting pidns failed");
/\* fork to get the passed in pid ns \*/
fork\_intermediate\_child ();
/\* We might both have specified an --pidns \*and\* --unshare-pid, so set up a new child pid namespace under the specified one \*/
if (opt\_unshare\_pid)
{
if (unshare (CLONE\_NEWPID))
die\_with\_error ("unshare pid ns");
/\* fork to get the new pid ns \*/
fork\_intermediate\_child ();
}
/\* We're back, either in a child or grandchild, so message the actual pid to the monitor \*/
close (intermediate\_pids\_sockets[0]);
send\_pid\_on\_socket (intermediate\_pids\_sockets[1]);
close (intermediate\_pids\_sockets[1]);
}
/\* Child, in sandbox, privileged in the parent or in the user namespace (if --unshare-user).
\*
\* Note that for user namespaces we run as euid 0 during clone(), so
\* the child user namespace is owned by euid 0., This means that the
\* regular user namespace parent (with uid != 0) doesn't have any
\* capabilities in it, which is nice as we can't exploit those. In
\* particular the parent user namespace doesn't have CAP\_PTRACE
\* which would otherwise allow the parent to hijack of the child
\* after this point.
\*
\* Unfortunately this also means you can't ptrace the final
\* sandboxed process from outside the sandbox either.
\*/
if (opt\_info\_fd != -1)
close (opt\_info\_fd);
if (opt\_json\_status\_fd != -1)
close (opt\_json\_status\_fd);
/\* Wait for the parent to init uid/gid maps and drop caps \*/
res = read (child\_wait\_fd, &val, 8);
close (child\_wait\_fd);
/\* At this point we can completely drop root uid, but retain the
\* required permitted caps. This allow us to do full setup as
\* the user uid, which makes e.g. fuse access work.
\*/
switch\_to\_user\_with\_privs ();
if (opt\_unshare\_net)
loopback\_setup (); /\* Will exit if unsuccessful \*/
ns\_uid = opt\_sandbox\_uid;
ns\_gid = opt\_sandbox\_gid;
if (!is\_privileged && opt\_unshare\_user && opt\_userns\_block\_fd == -1)
{
/\* In the unprivileged case we have to write the uid/gid maps in
\* the child, because we have no caps in the parent \*/
if (opt\_needs\_devpts)
{
/\* This is a bit hacky, but we need to first map the real uid/gid to
0, otherwise we can't mount the devpts filesystem because root is
not mapped. Later we will create another child user namespace and
map back to the real uid \*/
ns\_uid = 0;
ns\_gid = 0;
}
write\_uid\_gid\_map (ns\_uid, real\_uid,
ns\_gid, real\_gid,
-1, TRUE, FALSE);
}
old\_umask = umask (0);
/\* Need to do this before the chroot, but after we're the real uid \*/
resolve\_symlinks\_in\_ops ();
/\* Mark everything as slave, so that we still
\* receive mounts from the real root, but don't
\* propagate mounts to the real root. \*/
if (mount (NULL, "/", NULL, MS\_SILENT | MS\_SLAVE | MS\_REC, NULL) < 0)
die\_with\_error ("Failed to make / slave");
/\* Create a tmpfs which we will use as / in the namespace \*/
if (mount ("tmpfs", base\_path, "tmpfs", MS\_NODEV | MS\_NOSUID, NULL) != 0)
die\_with\_error ("Failed to mount tmpfs");
old\_cwd = get\_current\_dir\_name ();
/\* Chdir to the new root tmpfs mount. This will be the CWD during
the entire setup. Access old or new root via "oldroot" and "newroot". \*/
if (chdir (base\_path) != 0)
die\_with\_error ("chdir base\_path");
/\* We create a subdir "$base\_path/newroot" for the new root, that
\* way we can pivot\_root to base\_path, and put the old root at
\* "$base\_path/oldroot". This avoids problems accessing the oldroot
\* dir if the user requested to bind mount something over / (or
\* over /tmp, now that we use that for base\_path). \*/
if (mkdir ("newroot", 0755))
die\_with\_error ("Creating newroot failed");
if (mount ("newroot", "newroot", NULL, MS\_SILENT | MS\_MGC\_VAL | MS\_BIND | MS\_REC, NULL) < 0)
die\_with\_error ("setting up newroot bind");
if (mkdir ("oldroot", 0755))
die\_with\_error ("Creating oldroot failed");
if (pivot\_root (base\_path, "oldroot"))
die\_with\_error ("pivot\_root");
if (chdir ("/") != 0)
die\_with\_error ("chdir / (base path)");
if (is\_privileged)
{
pid\_t child;
int privsep\_sockets[2];
if (socketpair (AF\_UNIX, SOCK\_SEQPACKET | SOCK\_CLOEXEC, 0, privsep\_sockets) != 0)
die\_with\_error ("Can't create privsep socket");
child = fork ();
if (child == -1)
die\_with\_error ("Can't fork unprivileged helper");
if (child == 0)
{
/\* Unprivileged setup process \*/
drop\_privs (FALSE, TRUE);
close (privsep\_sockets[0]);
setup\_newroot (opt\_unshare\_pid, privsep\_sockets[1]);
exit (0);
}
else
{
int status;
uint32\_t buffer[2048]; /\* 8k, but is int32 to guarantee nice alignment \*/
uint32\_t op, flags, perms;
size\_t size\_arg;
const char \*arg1, \*arg2;
cleanup\_fd int unpriv\_socket = -1;
unpriv\_socket = privsep\_sockets[0];
close (privsep\_sockets[1]);
do
{
op = read\_priv\_sec\_op (unpriv\_socket, buffer, sizeof (buffer),
&flags, &perms, &size\_arg, &arg1, &arg2);
privileged\_op (-1, op, flags, perms, size\_arg, arg1, arg2);
if (write (unpriv\_socket, buffer, 1) != 1)
die ("Can't write to op\_socket");
}
while (op != PRIV\_SEP\_OP\_DONE);
waitpid (child, &status, 0);
/\* Continue post setup \*/
}
}
else
{
setup\_newroot (opt\_unshare\_pid, -1);
}
close\_ops\_fd ();
/\* The old root better be rprivate or we will send unmount events to the parent namespace \*/
if (mount ("oldroot", "oldroot", NULL, MS\_SILENT | MS\_REC | MS\_PRIVATE, NULL) != 0)
die\_with\_error ("Failed to make old root rprivate");
if (umount2 ("oldroot", MNT\_DETACH))
die\_with\_error ("unmount old root");
/\* This is our second pivot. It's like we're a Silicon Valley startup flush
\* with cash but short on ideas!
\*
\* We're aiming to make /newroot the real root, and get rid of /oldroot. To do
\* that we need a temporary place to store it before we can unmount it.
\*/
{ cleanup\_fd int oldrootfd = open ("/", O\_DIRECTORY | O\_RDONLY);
if (oldrootfd < 0)
die\_with\_error ("can't open /");
if (chdir ("/newroot") != 0)
die\_with\_error ("chdir /newroot");
/\* While the documentation claims that put\_old must be underneath
\* new\_root, it is perfectly fine to use the same directory as the
\* kernel checks only if old\_root is accessible from new\_root.
\*
\* Both runc and LXC are using this "alternative" method for
\* setting up the root of the container:
\*
\* https://github.com/opencontainers/runc/blob/HEAD/libcontainer/rootfs\_linux.go#L671
\* https://github.com/lxc/lxc/blob/HEAD/src/lxc/conf.c#L1121
\*/
if (pivot\_root (".", ".") != 0)
die\_with\_error ("pivot\_root(/newroot)");
if (fchdir (oldrootfd) < 0)
die\_with\_error ("fchdir to oldroot");
if (umount2 (".", MNT\_DETACH) < 0)
die\_with\_error ("umount old root");
if (chdir ("/") != 0)
die\_with\_error ("chdir /");
}
if (opt\_userns2\_fd > 0 && setns (opt\_userns2\_fd, CLONE\_NEWUSER) != 0)
die\_with\_error ("Setting userns2 failed");
if (opt\_unshare\_user && opt\_userns\_block\_fd == -1 &&
(ns\_uid != opt\_sandbox\_uid || ns\_gid != opt\_sandbox\_gid ||
opt\_disable\_userns))
{
/\* Here we create a second level userns inside the first one. This is
used for one or more of these reasons:
\* The 1st level namespace has a different uid/gid than the
requested due to requirements of beeing root in the first
level due for mounting devpts (opt\_needs\_devpts).
\* To disable user namespaces we set max\_user\_namespaces and then
create the second namespace so that the sandbox cannot undo this
change.
\*/
if (opt\_disable\_userns)
{
cleanup\_fd int sysctl\_fd = -1;
sysctl\_fd = openat (proc\_fd, "sys/user/max\_user\_namespaces", O\_WRONLY);
if (sysctl\_fd < 0)
die\_with\_error ("cannot open /proc/sys/user/max\_user\_namespaces");
if (write\_to\_fd (sysctl\_fd, "1", 1) < 0)
die\_with\_error ("sysctl user.max\_user\_namespaces = 1");
}
if (unshare (CLONE\_NEWUSER))
die\_with\_error ("unshare user ns");
/\* We're in a new user namespace, we got back the bounding set, clear it again \*/
drop\_cap\_bounding\_set (FALSE);
write\_uid\_gid\_map (opt\_sandbox\_uid, ns\_uid,
opt\_sandbox\_gid, ns\_gid,
-1, FALSE, FALSE);
}
if (opt\_disable\_userns || opt\_assert\_userns\_disabled)
{
/\* Verify that we can't make a new userns again \*/
res = unshare (CLONE\_NEWUSER);
if (res == 0)
die ("creation of new user namespaces was not disabled as requested");
}
/\* All privileged ops are done now, so drop caps we don't need \*/
drop\_privs (!is\_privileged, TRUE);
if (opt\_block\_fd != -1)
{
char b[1];
(void) TEMP\_FAILURE\_RETRY (read (opt\_block\_fd, b, 1));
close (opt\_block\_fd);
}
if (opt\_seccomp\_fd != -1)
{
assert (seccomp\_programs == NULL);
/\* takes ownership of fd \*/
seccomp\_program\_new (&opt\_seccomp\_fd);
}
umask (old\_umask);
new\_cwd = "/";
if (opt\_chdir\_path)
{
if (chdir (opt\_chdir\_path))
die\_with\_error ("Can't chdir to %s", opt\_chdir\_path);
new\_cwd = opt\_chdir\_path;
}
else if (chdir (old\_cwd) == 0)
{
/\* If the old cwd is mapped in the sandbox, go there \*/
new\_cwd = old\_cwd;
}
else
{
/\* If the old cwd is not mapped, go to home \*/
const char \*home = getenv ("HOME");
if (home != NULL &&
chdir (home) == 0)
new\_cwd = home;
}
xsetenv ("PWD", new\_cwd, 1);
free (old\_cwd);
if (opt\_new\_session &&
setsid () == (pid\_t) -1)
die\_with\_error ("setsid");
if (label\_exec (opt\_exec\_label) == -1)
die\_with\_error ("label\_exec %s", argv[0]);
\_\_debug\_\_ (("forking for child\n"));
if (!opt\_as\_pid\_1 && (opt\_unshare\_pid || lock\_files != NULL || opt\_sync\_fd != -1))
{
/\* We have to have a pid 1 in the pid namespace, because
\* otherwise we'll get a bunch of zombies as nothing reaps
\* them. Alternatively if we're using sync\_fd or lock\_files we
\* need some process to own these.
\*/
pid = fork ();
if (pid == -1)
die\_with\_error ("Can't fork for pid 1");
if (pid != 0)
{
drop\_all\_caps (FALSE);
/\* Close fds in pid 1, except stdio and optionally event\_fd
(for syncing pid 2 lifetime with monitor\_child) and
opt\_sync\_fd (for syncing sandbox lifetime with outside
process).
Any other fds will been passed on to the child though. \*/
{
int dont\_close[3];
int j = 0;
if (event\_fd != -1)
dont\_close[j++] = event\_fd;
if (opt\_sync\_fd != -1)
dont\_close[j++] = opt\_sync\_fd;
dont\_close[j++] = -1;
fdwalk (proc\_fd, close\_extra\_fds, dont\_close);
}
return do\_init (event\_fd, pid);
}
}
\_\_debug\_\_ (("launch executable %s\n", argv[0]));
if (proc\_fd != -1)
close (proc\_fd);
/\* If we are using --as-pid-1 leak the sync fd into the sandbox.
--sync-fd will still work unless the container process doesn't close this file. \*/
if (!opt\_as\_pid\_1)
{
if (opt\_sync\_fd != -1)
close (opt\_sync\_fd);
}
/\* We want sigchild in the child \*/
unblock\_sigchild ();
/\* Optionally bind our lifecycle \*/
handle\_die\_with\_parent ();
if (!is\_privileged)
set\_ambient\_capabilities ();
/\* Should be the last thing before execve() so that filters don't
\* need to handle anything above \*/
seccomp\_programs\_apply ();
if (setup\_finished\_pipe[1] != -1)
{
char data = 0;
res = write\_to\_fd (setup\_finished\_pipe[1], &data, 1);
/\* Ignore res, if e.g. the parent died and closed setup\_finished\_pipe[0]
we don't want to error out here \*/
}
if (execvp (argv[0], argv) == -1)
{
if (setup\_finished\_pipe[1] != -1)
{
int saved\_errno = errno;
char data = 0;
res = write\_to\_fd (setup\_finished\_pipe[1], &data, 1);
errno = saved\_errno;
/\* Ignore res, if e.g. the parent died and closed setup\_finished\_pipe[0]
we don't want to error out here \*/
}
die\_with\_error ("execvp %s", argv[0]);
}
return 0;
}