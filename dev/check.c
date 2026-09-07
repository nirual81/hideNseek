#define _POSIX_C_SOURCE 200809L
#include "../seeker/ProbeLogic.h"
#include <assert.h>
#include <fcntl.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <unistd.h>

int main(void) {
    assert(SKPresenceFromCall(0, EACCES) == SKPresent); // Ignore stale errno on success.
    assert(SKPresenceFromCall(-1, ENOENT) == SKAbsent);
    assert(SKPresenceFromCall(-1, ENOTDIR) == SKAbsent);
    assert(SKPresenceFromCall(-1, EACCES) == SKUnknown);
    assert(SKPresenceFromCall(-1, EPERM) == SKUnknown);
    assert(SKPresenceFromCall(-1, EIO) == SKUnknown);
    assert(SKDisagrees(SKPresent, SKAbsent));
    assert(!SKDisagrees(SKPresent, SKUnknown));
    assert(!SKDisagrees(SKAbsent, SKUnknown));
    assert(!strcmp(SKState(true, true), "FIRED"));
    assert(!strcmp(SKState(false, true), "UNAVAILABLE"));
    assert(!strcmp(SKState(false, false), "NOT OBSERVED"));

    char directory[] = "/tmp/seeker-check-XXXXXX";
    assert(mkdtemp(directory));
    char target[128], link[128];
    snprintf(target, sizeof(target), "%s/artifact", directory);
    snprintf(link, sizeof(link), "%s/link", directory);
    assert(symlink(target, link) == 0);
    struct stat st;
    assert(lstat(link, &st) == 0 && S_ISLNK(st.st_mode));
    int rc = stat(link, &st), code = errno;
    assert(SKPresenceFromCall(rc, code) == SKAbsent); // Legitimate dangling symlink.
    int fd = open(target, O_WRONLY | O_CREAT | O_EXCL, 0600);
    assert(fd >= 0);
    assert(close(fd) == 0);
    rc = stat(link, &st); code = errno;
    assert(SKPresenceFromCall(rc, code) == SKPresent && S_ISREG(st.st_mode));
    rc = access(link, F_OK); code = errno;
    assert(!SKDisagrees(SKPresent, SKPresenceFromCall(rc, code)));
    assert(unlink(link) == 0);
    assert(unlink(target) == 0);
    assert(rmdir(directory) == 0);
    puts("Probe logic and real filesystem edge cases passed.");
}
