/*
 * chrdev_test - user-space exerciser for /dev/chrdev_demo
 *
 * Cross-compiled by the top-level Makefile (zig cc, arm-linux-gnueabihf):
 *   make build/chrdev_test
 *   make upload      # scp to mp157
 *   ssh mp157 ~/_work/test/chrdev_test
 */

#include <fcntl.h>
#include <stdio.h>
#include <string.h>
#include <unistd.h>
#include <errno.h>
#include <sys/types.h>

#define DEV_PATH "/dev/chrdev_demo"

int main(void)
{
	const char msg[] = "hello from userspace\n";
	char  rbuf[128];
	ssize_t n;
	int fd;

	fd = open(DEV_PATH, O_RDWR);
	if (fd < 0) {
		fprintf(stderr, "open %s: %s\n", DEV_PATH, strerror(errno));
		return 1;
	}

	/* write */
	n = write(fd, msg, sizeof(msg) - 1);
	printf("write -> %zd\n", n);

	/* rewind and read back */
	if (lseek(fd, 0, SEEK_SET) < 0) {
		perror("lseek");
		close(fd);
		return 1;
	}

	memset(rbuf, 0, sizeof(rbuf));
	n = read(fd, rbuf, sizeof(rbuf) - 1);
	printf("read  -> %zd: \"%s\"\n", n, rbuf);

	close(fd);
	return 0;
}
