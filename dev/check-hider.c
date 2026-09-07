#define _XOPEN_SOURCE 700
#include <assert.h>
#include <stdlib.h>
#include <sys/stat.h>
#include <unistd.h>
#include "../hider/PathPolicy.h"

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
    assert(unlink(alias) == 0);
    assert(rmdir(root) == 0);
    assert(rmdir(dir) == 0);
    puts("Hider policy passed: boundaries, dot components, private aliases, bootstrap aliases, missing children.");
}
