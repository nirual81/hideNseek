#ifndef HS_PATH_POLICY_H
#define HS_PATH_POLICY_H
#include <stdbool.h>
#include <stddef.h>
#include <stdio.h>
#include <string.h>

#define HS_PATH_MAX 4096

static bool HSUnder(const char *path, const char *root) {
    size_t n = strlen(root);
    return n > 1 && !strncmp(path, root, n) && (path[n] == 0 || path[n] == '/');
}

static bool HSKnownPath(const char *path, const char *bootstrap) {
    if (HSUnder(path, "/private/var") || HSUnder(path, "/private/etc")) path += 8;
    static const char *const roots[] = {
        "/var/jb", "/var/Liy", "/etc/apt", "/etc/ssh/sshd_config",
        "/Applications/Cydia.app", "/Applications/Sileo.app", "/Applications/Zebra.app",
        "/Applications/Filza.app", "/Applications/Dopamine.app",
        "/Library/MobileSubstrate", "/Library/TweakInject", "/usr/lib/TweakInject",
        "/usr/lib/libellekit.dylib", "/usr/lib/libsubstrate.dylib",
        "/usr/sbin/frida-server", "/usr/sbin/sshd", "/var/lib/dpkg", "/var/lib/apt",
        "/var/cache/apt", "/var/log/apt",
        "/var/mobile/Library/Preferences/me.jjolano.shadow.plist",
        "/var/mobile/Library/Preferences/com.opa334.Dopamine.plist"
    };
    for (size_t i = 0; i < sizeof roots / sizeof *roots; ++i)
        if (HSUnder(path, roots[i])) return true;
    if (!strncmp(path, "/var/.jbroot-", 13) && path[13] && path[13] != '/') return true;
    if (bootstrap && *bootstrap) {
        if (HSUnder(bootstrap, "/private/var") || HSUnder(bootstrap, "/private/etc")) bootstrap += 8;
        if (HSUnder(path, bootstrap)) return true;
    }
    return false;
}

// Walk components so /var/jb/../mobile also fails at the hidden component.
static bool HSLexicalHidden(const char *path, const char *bootstrap) {
    if (!path || path[0] != '/' || strlen(path) >= HS_PATH_MAX) return false;
    char clean[HS_PATH_MAX] = "/";
    size_t used = 1;
    while (*path) {
        while (*path == '/') ++path;
        const char *part = path;
        while (*path && *path != '/') ++path;
        size_t n = (size_t)(path - part);
        if (!n || (n == 1 && part[0] == '.')) continue;
        if (n == 2 && !strncmp(part, "..", 2)) {
            while (used > 1 && clean[--used] != '/') {}
            clean[used] = 0;
            continue;
        }
        if (used > 1) clean[used++] = '/';
        memcpy(clean + used, part, n);
        clean[used += n] = 0;
        if (HSKnownPath(clean, bootstrap)) return true;
    }
    return false;
}

// resolve is the original realpath. Existing aliases and missing children of
// existing aliases use the same policy. Failed resolution leaves libc in charge.
// ponytail: fixed path list and per-call resolution; extend for a measured miss,
// not a cached virtual filesystem (which would need invalidation on every write).
static bool HSHiddenAbsolute(const char *path, const char *bootstrap,
                             char *(*resolve)(const char *, char *)) {
    if (!path || path[0] != '/' || strlen(path) >= HS_PATH_MAX) return false;
    if (HSLexicalHidden(path, bootstrap)) return true;
    char candidate[HS_PATH_MAX], resolved[HS_PATH_MAX];
    snprintf(candidate, sizeof candidate, "%s", path);
    do {
        if (resolve(candidate, resolved)) return HSLexicalHidden(resolved, bootstrap);
        char *slash = strrchr(candidate, '/');
        if (!slash || slash == candidate) break;
        *slash = 0;
    } while (*candidate);
    return false;
}
#endif
