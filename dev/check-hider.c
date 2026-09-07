#define _XOPEN_SOURCE 700
#include <assert.h>
#include <stdlib.h>
#include <sys/stat.h>
#include <sys/wait.h>
#include <unistd.h>
#include "../hider/PathPolicy.h"
#include "../hider/StartupTrace.h"

int main(void) {
    const char *blocked[] = {
        "/var/jb", "/var/jb/", "/var/jb/usr/lib/libellekit.dylib",
        "/private/var/jb", "//private//var/./jb", "/var/mobile/../jb",
        "/var/jb/../mobile", "/private/etc/apt/sources.list",
        "/var/.jbroot-1234/usr/lib", "/Applications/Sileo.app/Info.plist",
        "/var/mobile/Library/Preferences/me.jjolano.shadow.plist",
        "/private/preboot/ABC/dopamine/procursus/usr/lib"
    };
    const char *allowed[] = {
        "/", "/var", "/private/var/mobile", "/var/jboss", "/var/jb-backup",
        "/var/mobile/Documents/var/jb", "/var/.jbroot-", "/var/.jbroot",
        "/Applications/Sileo.application", "/etc/aptitude", "/usr/lib/libSystem.B.dylib",
        "/private/preboot/ABC/dopamine/procursus-other", "/a/../../var/mobile"
    };
    const char *bootstrap = "/private/preboot/ABC/dopamine/procursus";
    for (size_t i = 0; i < sizeof blocked / sizeof *blocked; ++i) assert(HSLexicalHidden(blocked[i], bootstrap));
    for (size_t i = 0; i < sizeof allowed / sizeof *allowed; ++i) assert(!HSLexicalHidden(allowed[i], bootstrap));
    assert(!HSLexicalHidden(NULL, NULL));
    assert(!HSLexicalHidden("", NULL));
    assert(!HSLexicalHidden("var/jb", NULL));
    char longPath[HS_PATH_MAX + 1];
    memset(longPath, 'a', sizeof longPath); longPath[0] = '/'; longPath[HS_PATH_MAX] = 0;
    assert(!HSLexicalHidden(longPath, NULL));

    // Actual symlink resolution, including a nonexistent child under an alias.
    char temporary[] = "/tmp/hider-check-XXXXXX";
    char *dir = mkdtemp(temporary);
    assert(dir);
    char root[HS_PATH_MAX], alias[HS_PATH_MAX], missing[HS_PATH_MAX];
    assert(snprintf(root, sizeof root, "%s/bootstrap", dir) < HS_PATH_MAX);
    assert(snprintf(alias, sizeof alias, "%s/alias", dir) < HS_PATH_MAX);
    assert(snprintf(missing, sizeof missing, "%s/alias/not-created/file", dir) < HS_PATH_MAX);
    assert(mkdir(root, 0700) == 0);
    assert(symlink(root, alias) == 0);
    assert(HSHiddenAbsolute(alias, root, realpath));
    assert(HSHiddenAbsolute(missing, root, realpath));
    assert(!HSHiddenAbsolute(dir, root, realpath));
    assert(!HSHiddenAbsolute(alias, NULL, realpath));

    // Real diagnostic writes survive closing the descriptor and preserve errno.
    // Reusing a template creates a different private file, never overwrites one.
    char trace[HS_PATH_MAX], second[HS_PATH_MAX], text[256] = {0};
    assert(snprintf(trace, sizeof trace, "%s/Hider-startup-XXXXXX", dir) < HS_PATH_MAX);
    strcpy(second, trace);
    errno = EACCES;
    int fd = HSOpenTrace(trace);
    assert(fd >= 0 && errno == EACCES);
    struct stat info;
    assert(fstat(fd, &info) == 0 && (info.st_mode & 0777) == 0600);
    assert(fcntl(fd, F_GETFD) & FD_CLOEXEC);
    errno = EBUSY;
    HSWriteTrace(fd, "c/before", "access");
    HSWriteTrace(fd, "c/after", "access");
    assert(errno == EBUSY);
    assert(lseek(fd, 0, SEEK_SET) == 0);
    assert(read(fd, text, sizeof text - 1) > 0);
    assert(!strcmp(text, "c/before access\nc/after access\n"));
    assert(close(fd) == 0);
    fd = HSOpenTrace(second);
    assert(fd >= 0 && strcmp(trace, second));
    pid_t child = fork();
    assert(child >= 0);
    if (!child) {
        HSWriteTrace(fd, "c/before", "child-exit");
        _exit(17); // No stdio flush or explicit close: the checkpoint must still exist.
    }
    int childStatus;
    assert(waitpid(child, &childStatus, 0) == child);
    assert(WIFEXITED(childStatus) && WEXITSTATUS(childStatus) == 17);
    assert(lseek(fd, 0, SEEK_SET) == 0);
    memset(text, 0, sizeof text);
    assert(read(fd, text, sizeof text - 1) > 0);
    assert(!strcmp(text, "c/before child-exit\n"));
    assert(close(fd) == 0);
    errno = EAGAIN;
    HSWriteTrace(-1, "unavailable", "ignored");
    assert(errno == EAGAIN);
    assert(unlink(trace) == 0 && unlink(second) == 0);
    assert(unlink(alias) == 0);
    assert(rmdir(root) == 0);
    assert(rmdir(dir) == 0);
    puts("Hider policy passed: boundaries, dot components, private aliases, bootstrap aliases, missing children.");
    puts("Startup trace passed: exclusive files, mode 0600, close-on-exec, contents, child-exit persistence and errno preservation.");
}
