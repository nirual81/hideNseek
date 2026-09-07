#import <Foundation/Foundation.h>
#import <substrate.h>
#include <dirent.h>
#include <dlfcn.h>
#include <errno.h>
#include <fcntl.h>
#include <stdarg.h>
#include <stdlib.h>
#include <sys/attr.h>
#include <sys/mount.h>
#include <sys/stat.h>
#include <sys/statvfs.h>
#include <unistd.h>
#import "Config.h"
#include "PathPolicy.h"

static char bootstrap[HS_PATH_MAX];
static __thread unsigned resolving;
static char *(*original_realpath)(const char *, char *);

static bool hiddenAt(int directory, const char *path) {
    if (resolving || !path || !*path) return false;
    int saved = errno;
    ++resolving;
    char absolute[HS_PATH_MAX], base[HS_PATH_MAX];
    bool hidden = false;
    if (path[0] == '/') hidden = HSHiddenAbsolute(path, bootstrap, original_realpath);
    else if ((directory == AT_FDCWD ? getcwd(base, sizeof base) != NULL : fcntl(directory, F_GETPATH, base) == 0) &&
             snprintf(absolute, sizeof absolute, "%s/%s", base, path) < (int)sizeof absolute)
        hidden = HSHiddenAbsolute(absolute, bootstrap, original_realpath);
    --resolving;
    errno = saved;
    return hidden;
}
static bool hidden(const char *path) { return hiddenAt(AT_FDCWD, path); }
static BOOL hiddenString(NSString *path) { return path && hidden(path.fileSystemRepresentation); }
static BOOL hiddenURL(NSURL *url) { return url.isFileURL && hiddenString(url.path); }
static int missing(void) { errno = ENOENT; return -1; }
static void missingError(NSError **error, NSString *path) {
    if (error) *error = [NSError errorWithDomain:NSCocoaErrorDomain code:NSFileReadNoSuchFileError userInfo:@{
        NSFilePathErrorKey: path ?: @"",
        NSUnderlyingErrorKey: [NSError errorWithDomain:NSPOSIXErrorDomain code:ENOENT userInfo:nil]
    }];
}

#define PATH_CALL(name, type, parameter) \
    static int (*original_##name)(const char *, type); \
    static int replaced_##name(const char *path, type parameter) { \
        return hidden(path) ? missing() : original_##name(path, parameter); \
    }
PATH_CALL(access, int, mode)
PATH_CALL(stat, struct stat *, result)
PATH_CALL(lstat, struct stat *, result)
PATH_CALL(statfs, struct statfs *, result)
PATH_CALL(statvfs, struct statvfs *, result)

static int (*original_faccessat)(int, const char *, int, int);
static int replaced_faccessat(int fd, const char *path, int mode, int flags) {
    return hiddenAt(fd, path) ? missing() : original_faccessat(fd, path, mode, flags);
}
static int (*original_fstatat)(int, const char *, struct stat *, int);
static int replaced_fstatat(int fd, const char *path, struct stat *result, int flags) {
    return hiddenAt(fd, path) ? missing() : original_fstatat(fd, path, result, flags);
}
static int (*original_getattrlist)(const char *, struct attrlist *, void *, size_t, unsigned long);
static int replaced_getattrlist(const char *path, struct attrlist *attrs, void *buffer, size_t size, unsigned long options) {
    return hidden(path) ? missing() : original_getattrlist(path, attrs, buffer, size, options);
}
static int (*original_getattrlistat)(int, const char *, struct attrlist *, void *, size_t, unsigned long);
static int replaced_getattrlistat(int fd, const char *path, struct attrlist *attrs, void *buffer, size_t size, unsigned long options) {
    return hiddenAt(fd, path) ? missing() : original_getattrlistat(fd, path, attrs, buffer, size, options);
}
static ssize_t (*original_readlink)(const char *, char *, size_t);
static ssize_t replaced_readlink(const char *path, char *buffer, size_t size) {
    return hidden(path) ? missing() : original_readlink(path, buffer, size);
}
static ssize_t (*original_readlinkat)(int, const char *, char *, size_t);
static ssize_t replaced_readlinkat(int fd, const char *path, char *buffer, size_t size) {
    return hiddenAt(fd, path) ? missing() : original_readlinkat(fd, path, buffer, size);
}
static char *replaced_realpath(const char *path, char *result) {
    if (hidden(path)) { missing(); return NULL; }
    return original_realpath(path, result);
}

// Darwin's mode is variadic only with O_CREAT; do not read a nonexistent argument.
#define OPEN_CALL(name) \
    static int (*original_##name)(const char *, int, ...); \
    static int replaced_##name(const char *path, int flags, ...) { \
        if (hidden(path)) return missing(); \
        if (!(flags & O_CREAT)) return original_##name(path, flags); \
        va_list args; va_start(args, flags); int mode = va_arg(args, int); va_end(args); \
        return original_##name(path, flags, mode); \
    }
OPEN_CALL(open)
OPEN_CALL(open_nocancel)
#define OPENAT_CALL(name) \
    static int (*original_##name)(int, const char *, int, ...); \
    static int replaced_##name(int fd, const char *path, int flags, ...) { \
        if (hiddenAt(fd, path)) return missing(); \
        if (!(flags & O_CREAT)) return original_##name(fd, path, flags); \
        va_list args; va_start(args, flags); int mode = va_arg(args, int); va_end(args); \
        return original_##name(fd, path, flags, mode); \
    }
OPENAT_CALL(openat)
OPENAT_CALL(openat_nocancel)

static FILE *(*original_fopen)(const char *, const char *);
static FILE *replaced_fopen(const char *path, const char *mode) {
    if (hidden(path)) { missing(); return NULL; }
    return original_fopen(path, mode);
}
static DIR *(*original_opendir)(const char *);
static DIR *replaced_opendir(const char *path) {
    if (hidden(path)) { missing(); return NULL; }
    return original_opendir(path);
}
static bool hiddenEntry(DIR *dir, const char *name) {
    if (!strcmp(name, ".") || !strcmp(name, "..")) return false;
    return hiddenAt(dirfd(dir), name);
}
static struct dirent *(*original_readdir)(DIR *);
static struct dirent *replaced_readdir(DIR *dir) {
    struct dirent *entry;
    do { entry = original_readdir(dir); } while (entry && hiddenEntry(dir, entry->d_name));
    return entry;
}
static int (*original_readdir_r)(DIR *, struct dirent *, struct dirent **);
static int replaced_readdir_r(DIR *dir, struct dirent *entry, struct dirent **result) {
    int status;
    do { status = original_readdir_r(dir, entry, result); }
    while (!status && *result && hiddenEntry(dir, (*result)->d_name));
    return status;
}

static NSArray *visibleItems(NSArray *items, NSString *base) {
    if (!items) return nil;
    NSMutableArray *visible = [NSMutableArray arrayWithCapacity:items.count];
    for (id item in items) {
        BOOL hide = [item isKindOfClass:NSURL.class] ? hiddenURL(item) : hiddenString([base stringByAppendingPathComponent:item]);
        if (!hide) [visible addObject:item];
    }
    return visible;
}

// Keep lazy traversal and skipDescendants semantics. No eager directory tree copy.
@interface HSDirectoryEnumerator : NSDirectoryEnumerator
@property(nonatomic) NSDirectoryEnumerator *inner;
@property(nonatomic) NSString *base;
@property(nonatomic) NSMutableArray *batch;
@end
@implementation HSDirectoryEnumerator
- (id)nextObject {
    id item;
    while ((item = [self.inner nextObject])) {
        BOOL hide = [item isKindOfClass:NSURL.class] ? hiddenURL(item) : hiddenString([self.base stringByAppendingPathComponent:item]);
        if (!hide) return item;
        [self.inner skipDescendants];
    }
    return nil;
}
- (NSUInteger)countByEnumeratingWithState:(NSFastEnumerationState *)state objects:(id __unsafe_unretained [])buffer count:(NSUInteger)count {
    // NSEnumerator's fast enumeration must call our filtered nextObject.
    self.batch = [NSMutableArray arrayWithCapacity:count];
    NSUInteger used = 0;
    while (used < count) {
        id item = [self nextObject];
        if (!item) break;
        [self.batch addObject:item];
        buffer[used++] = item;
    }
    state->itemsPtr = buffer;
    state->mutationsPtr = &state->extra[0];
    state->state += used;
    return used;
}
- (NSDictionary *)fileAttributes { return self.inner.fileAttributes; }
- (NSDictionary *)directoryAttributes { return self.inner.directoryAttributes; }
- (NSUInteger)level { return self.inner.level; }
- (void)skipDescendants { [self.inner skipDescendants]; }
- (void)skipDescendents { [self.inner skipDescendants]; }
@end
static NSDirectoryEnumerator *filteredEnumerator(NSDirectoryEnumerator *inner, NSString *base) {
    if (!inner) return nil;
    HSDirectoryEnumerator *result = [HSDirectoryEnumerator new];
    result.inner = inner;
    result.base = base.isAbsolutePath ? base : [NSFileManager.defaultManager.currentDirectoryPath stringByAppendingPathComponent:base];
    return result;
}

%group Filesystem
%hook NSFileManager
- (BOOL)fileExistsAtPath:(NSString *)path {
    return hiddenString(path) ? NO : %orig;
}
- (BOOL)fileExistsAtPath:(NSString *)path isDirectory:(BOOL *)directory {
    if (hiddenString(path)) { if (directory) *directory = NO; return NO; }
    return %orig;
}
- (BOOL)isReadableFileAtPath:(NSString *)path {
    return hiddenString(path) ? NO : %orig;
}
- (BOOL)isWritableFileAtPath:(NSString *)path {
    return hiddenString(path) ? NO : %orig;
}
- (BOOL)isExecutableFileAtPath:(NSString *)path {
    return hiddenString(path) ? NO : %orig;
}
- (BOOL)isDeletableFileAtPath:(NSString *)path {
    return hiddenString(path) ? NO : %orig;
}
- (NSData *)contentsAtPath:(NSString *)path {
    return hiddenString(path) ? nil : %orig;
}
- (NSDictionary *)attributesOfItemAtPath:(NSString *)path error:(NSError **)error {
    if (hiddenString(path)) { missingError(error, path); return nil; }
    return %orig;
}
- (NSDictionary *)attributesOfFileSystemForPath:(NSString *)path error:(NSError **)error {
    if (hiddenString(path)) { missingError(error, path); return nil; }
    return %orig;
}
- (NSString *)destinationOfSymbolicLinkAtPath:(NSString *)path error:(NSError **)error {
    if (hiddenString(path)) { missingError(error, path); return nil; }
    return %orig;
}
- (NSArray *)contentsOfDirectoryAtPath:(NSString *)path error:(NSError **)error {
    if (hiddenString(path)) { missingError(error, path); return nil; }
    NSArray *items = %orig;
    return visibleItems(items, path);
}
- (NSArray *)subpathsOfDirectoryAtPath:(NSString *)path error:(NSError **)error {
    if (hiddenString(path)) { missingError(error, path); return nil; }
    NSArray *items = %orig;
    return visibleItems(items, path);
}
- (NSArray *)subpathsAtPath:(NSString *)path {
    if (hiddenString(path)) return nil;
    NSArray *items = %orig;
    return visibleItems(items, path);
}
- (NSArray *)contentsOfDirectoryAtURL:(NSURL *)url includingPropertiesForKeys:(NSArray *)keys options:(NSDirectoryEnumerationOptions)options error:(NSError **)error {
    if (hiddenURL(url)) { missingError(error, url.path); return nil; }
    NSArray *items = %orig;
    return visibleItems(items, url.path);
}
- (NSDirectoryEnumerator *)enumeratorAtPath:(NSString *)path {
    if (hiddenString(path)) return nil;
    NSDirectoryEnumerator *inner = %orig;
    return filteredEnumerator(inner, path);
}
- (NSDirectoryEnumerator *)enumeratorAtURL:(NSURL *)url includingPropertiesForKeys:(NSArray *)keys options:(NSDirectoryEnumerationOptions)options errorHandler:(BOOL (^)(NSURL *, NSError *))handler {
    if (hiddenURL(url)) return nil;
    NSDirectoryEnumerator *inner = %orig;
    return filteredEnumerator(inner, url.path);
}
%end
%hook NSURL
- (BOOL)checkResourceIsReachableAndReturnError:(NSError **)error {
    if (hiddenURL(self)) { missingError(error, self.path); return NO; }
    return %orig;
}
- (BOOL)getResourceValue:(id *)value forKey:(NSString *)key error:(NSError **)error {
    if (hiddenURL(self)) { if (value) *value = nil; missingError(error, self.path); return NO; }
    return %orig;
}
- (NSDictionary *)resourceValuesForKeys:(NSArray *)keys error:(NSError **)error {
    if (hiddenURL(self)) { missingError(error, self.path); return nil; }
    return %orig;
}
%end
%end

// A symbol can have aliases. Patch each address once, leaving optional absent
// exports alone. Hook installation runs only during this library's constructor.
static void hook(const char *name, void *replacement, void **original) {
    static void *patched[32];
    static size_t count;
    void *symbol = dlsym(RTLD_DEFAULT, name);
    if (!symbol) return;
    for (size_t i = 0; i < count; ++i) if (patched[i] == symbol) return;
    if (count == sizeof patched / sizeof *patched) return;
    MSHookFunction(symbol, replacement, original);
    patched[count++] = symbol;
}
#define HOOK(name) hook(#name, (void *)replaced_##name, (void **)&original_##name)

%ctor {
    @autoreleasepool {
        NSString *identifier = NSBundle.mainBundle.bundleIdentifier;
        if (!identifier || HSProtectedApp(identifier) || ![NSBundle.mainBundle.bundlePath.pathExtension isEqualToString:@"app"]) return;
        if (![HSReadApps(NULL) containsObject:identifier]) return;
        original_realpath = realpath;
        char resolvedRoot[HS_PATH_MAX];
        if (realpath("/var/jb", resolvedRoot)) snprintf(bootstrap, sizeof bootstrap, "%s", resolvedRoot);
        HOOK(access); HOOK(stat); HOOK(lstat); HOOK(statfs); HOOK(statvfs);
        HOOK(faccessat); HOOK(fstatat); HOOK(getattrlist); HOOK(getattrlistat);
        HOOK(open); HOOK(openat); HOOK(fopen); HOOK(opendir);
        hook("open$NOCANCEL", (void *)replaced_open_nocancel, (void **)&original_open_nocancel);
        hook("openat$NOCANCEL", (void *)replaced_openat_nocancel, (void **)&original_openat_nocancel);
        HOOK(readdir); HOOK(readdir_r); HOOK(readlink); HOOK(readlinkat); HOOK(realpath);
        %init(Filesystem);
    }
}
