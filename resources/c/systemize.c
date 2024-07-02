#if 0
gcc -Os -fPIC -shared -o systemize.so $0
exit $?
#endif

#include <fcntl.h>
#include <sys/socket.h>
#include <sys/un.h>
#include <netinet/in.h>
#include <arpa/inet.h>
#include <dlfcn.h>
#include <stdlib.h>
#include <limits.h>
#include <unistd.h>
#include <string.h>
#include <errno.h>

static unsigned getenv_num(const char *name) {
	char *env = getenv(name);
	if (env) {
		char *end = NULL;
		long result = strtol(env, &end, 10);
		if (result > 0 && result < UINT_MAX && end && !*end) {
			return result;
		}
	}
	return 0;
}

static inline int is_listen_socket(const struct sockaddr *addr, socklen_t addrlen) {
	if (addr->sa_family == AF_INET && addrlen >= sizeof (struct sockaddr_in)) {
		struct sockaddr_in *sin = (struct sockaddr_in*) addr;
		if (!sin->sin_addr.s_addr && sin->sin_port == htons(1))
			return 1;
	} else if (addr->sa_family == AF_UNIX && addrlen >= 24) {
		struct sockaddr_un *sun = (struct sockaddr_un*) addr;
		if (!memcmp(sun->sun_path, "systemd/socket", 15))
			return 1;
	}
	return 0;
}

int bind(int sockfd, const struct sockaddr *addr, socklen_t addrlen) {
	static int(*bind_p)(int, const struct sockaddr*, socklen_t) = NULL;
	static int bind_done;

	if (is_listen_socket(addr, addrlen) && getenv_num("LISTEN_FDS") &&
			getpid() == getenv_num("LISTEN_PID")) {
		if (bind_done) {
			errno = EADDRINUSE;
			return -1;
		}
		int flags = fcntl(sockfd, F_GETFL);
		int fd = dup2(3, sockfd);
		if (fd == -1)
			return fd;
		if (flags != -1)
			fcntl(sockfd, F_SETFL, flags);
		close(3);
		bind_done = 1;
		// TODO notify
		return 0;
	}

	if (bind_p || (bind_p = dlsym(RTLD_NEXT, "bind")))
		return bind_p(sockfd, addr, addrlen);
	errno = ENOSYS;
	return -1;
}
