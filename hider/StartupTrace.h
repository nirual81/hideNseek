#ifndef HS_STARTUP_TRACE_H
#define HS_STARTUP_TRACE_H
#include <errno.h>
#include <fcntl.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

// Diagnostic-only, one private file per selected launch. No signal handlers or
// app data. Remove these checkpoints once the device failure is isolated.
static int HSOpenTrace(char *pathTemplate) {
    int saved = errno;
    int fd = mkstemp(pathTemplate); // Exclusive creation, mode 0600; never truncate an existing file.
    if (fd >= 0 && fcntl(fd, F_SETFD, FD_CLOEXEC) < 0) { close(fd); fd = -1; }
    errno = saved;
    return fd;
}

static void HSWriteTrace(int fd, const char *stage, const char *detail) {
    int saved = errno;
    if (fd >= 0) {
        char line[256];
        int count = snprintf(line, sizeof line, "%s %s\n", stage, detail);
        if (count > 0) {
            size_t left = (size_t)count < sizeof line ? (size_t)count : sizeof line - 1;
            const char *next = line;
            while (left) {
                ssize_t written = write(fd, next, left);
                if (written < 0 && errno == EINTR) continue;
                if (written <= 0) break;
                next += written;
                left -= (size_t)written;
            }
        }
    }
    errno = saved;
}
#endif
