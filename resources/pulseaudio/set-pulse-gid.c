#if 0
cc -o set-pulse-gid.so -Os -W -fno-strict-aliasing -fPIC -shared set-pulse-gid.c -ldl
strip --strip-all set-pulse-gid.so
exit 0
#endif

#define _GNU_SOURCE
#include <dlfcn.h>
#include <errno.h>
#include <sys/types.h>
#include <pwd.h>
#include <stdlib.h>

int setresgid(gid_t rgid, gid_t egid, gid_t sgid) {
	static int (*set_resgid)(gid_t rgid, gid_t egid, gid_t sgid) = 0;
	static gid_t pulse_group = 0;

	if (!set_resgid) {
		struct passwd *pw;
		if (!(set_resgid = dlsym(RTLD_NEXT, "setresgid"))) {
			errno = ENOSYS;
			return -1;
		}
	       	if ((pw = getpwnam("pulse"))) {
			pulse_group = pw->pw_gid;
		}
	}
	if (rgid == pulse_group && rgid) {
		const char *pgroup = getenv("PULSE_GROUP");
		rgid = 0;
		if (pgroup) {
			rgid = atoi(pgroup);
		}
		if (rgid == 0) {
			rgid = 1000;
		}
		sgid = egid = rgid;
	}
	return set_resgid(rgid, egid, sgid);
}
