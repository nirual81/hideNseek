#import "Detection.h"
#import "ProbeLogic.h"
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import <mach-o/dyld.h>
#import <mach-o/loader.h>
#import <mach/mach.h>
#include <arpa/inet.h>
#include <dlfcn.h>
#include <fcntl.h>
#include <poll.h>
#include <signal.h>
#include <sys/mount.h>
#include <sys/stat.h>
#include <sys/statvfs.h>
#include <sys/sysctl.h>
#include <sys/wait.h>
#include <unistd.h>

extern kern_return_t bootstrap_look_up(mach_port_t, const char *, mach_port_t *);

static NSString *Error(int code) { return [NSString stringWithFormat:@"%s (errno %d)", strerror(code), code]; }
static void Add(NSMutableArray *rows, NSString *category, NSString *name, BOOL found, BOOL incomplete, NSString *evidence) {
    [rows addObject:@{@"category":category, @"name":name, @"state":@(SKState(found, incomplete)), @"evidence":evidence}];
}
static void List(NSMutableArray *rows, NSString *category, NSString *name, NSArray *hits, NSArray *errors, NSString *empty) {
    NSMutableArray *lines = [hits mutableCopy];
    [lines addObjectsFromArray:errors];
    Add(rows, category, name, hits.count > 0, errors.count > 0, lines.count ? [lines componentsJoinedByString:@"\n"] : empty);
}
static enum SKPresence FoundationPresence(NSDictionary *attributes, NSError *error) {
    if (attributes) return SKPresent;
    if ([error.domain isEqual:NSCocoaErrorDomain] && (error.code == NSFileReadNoSuchFileError || error.code == NSFileNoSuchFileError)) return SKAbsent;
    return SKUnknown;
}

static void Filesystem(NSMutableArray *rows) {
    NSArray *paths = @[@"/var/jb", @"/var/jb/.procursus_strapped", @"/var/jb/basebin", @"/var/Liy",
        @"/var/jb/var/lib/dpkg/status", @"/var/jb/etc/apt", @"/var/jb/usr/lib/libellekit.dylib",
        @"/var/jb/Library/MobileSubstrate/DynamicLibraries", @"/var/jb/Library/LaunchDaemons",
        @"/var/jb/Applications/Sileo.app", @"/var/jb/Applications/Zebra.app", @"/var/jb/Applications/Filza.app",
        @"/Applications/Cydia.app", @"/Applications/Sileo.app", @"/Applications/Dopamine.app",
        @"/Library/MobileSubstrate/MobileSubstrate.dylib", @"/etc/apt", @"/usr/sbin/frida-server",
        @"/var/jb/usr/sbin/frida-server", @"/var/mobile/Library/Preferences/me.jjolano.shadow.plist",
        @"/var/mobile/Library/Preferences/com.opa334.Dopamine.plist"];
    NSArray *names = @[@"Foundation metadata", @"stat", @"lstat", @"access(F_OK)", @"open(O_RDONLY)"];
    NSMutableArray *hits[5], *errors[5];
    for (int i = 0; i < 5; i++) { hits[i] = [NSMutableArray array]; errors[i] = [NSMutableArray array]; }
    NSMutableArray *mismatches = [NSMutableArray array], *uncertain = [NSMutableArray array];
    for (NSString *path in paths) {
        const char *p = path.fileSystemRepresentation;
        NSError *error = nil;
        NSDictionary *attrs = [[NSFileManager defaultManager] attributesOfItemAtPath:path error:&error];
        struct stat st = {0}, lst = {0};
        enum SKPresence views[5]; int codes[5] = {0};
        views[0] = FoundationPresence(attrs, error);
        int rc = stat(p, &st); codes[1] = errno; views[1] = SKPresenceFromCall(rc, codes[1]);
        rc = lstat(p, &lst); codes[2] = errno; views[2] = SKPresenceFromCall(rc, codes[2]);
        rc = access(p, F_OK); codes[3] = errno; views[3] = SKPresenceFromCall(rc, codes[3]);
        int fd = open(p, O_RDONLY | O_NONBLOCK | O_CLOEXEC); codes[4] = errno;
        views[4] = SKPresenceFromCall(fd, codes[4]);
        if (fd >= 0) close(fd);
        for (int i = 0; i < 5; i++) {
            if (views[i] == SKPresent) {
                NSString *detail = i == 2 ? [NSString stringWithFormat:@"%@ (mode %o, uid %u, inode %llu)", path, lst.st_mode, lst.st_uid, (unsigned long long)lst.st_ino] : path;
                [hits[i] addObject:detail];
            }
            if (views[i] == SKUnknown) [errors[i] addObject:[NSString stringWithFormat:@"%@: %@", path, i == 0 ? (error.localizedDescription ?: @"Unknown Foundation error") : Error(codes[i])]];
        }
        // Compare only equivalent views. lstat may see a dangling link while stat cannot follow it.
        if (SKDisagrees(views[0], views[2]) || SKDisagrees(views[1], views[3]) || SKDisagrees(views[1], views[4]))
            [mismatches addObject:[NSString stringWithFormat:@"%@: Foundation=%d stat=%d lstat=%d access=%d open=%d", path, views[0], views[1], views[2], views[3], views[4]]];
        for (int i = 0; i < 5; i++) if (views[i] == SKUnknown) { [uncertain addObject:[path stringByAppendingString:@": one or more views blocked"]]; break; }
    }
    for (int i = 0; i < 5; i++) List(rows, @"Filesystem", names[i], hits[i], errors[i], @"No listed artifacts observed.");

    NSError *dirError = nil;
    NSArray *contents = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:@"/var" error:&dirError];
    NSMutableArray *entries = [NSMutableArray array];
    for (NSString *entry in contents) if ([entry isEqual:@"jb"] || [entry isEqual:@"Liy"] || [entry hasPrefix:@".jbroot-"]) [entries addObject:[@"/var/" stringByAppendingString:entry]];
    List(rows, @"Filesystem", @"Directory enumeration", entries, dirError ? @[dirError.localizedDescription] : @[], @"No bootstrap names in /var.");
    struct stat st;
    int rc = lstat("/var/jb", &st), code = errno;
    if (contents && SKDisagrees([contents containsObject:@"jb"] ? SKPresent : SKAbsent, SKPresenceFromCall(rc, code)))
        [mismatches addObject:@"/var enumeration disagrees with lstat(/var/jb)."];
    if (!contents) [uncertain addObject:@"/var enumeration unavailable."];
    List(rows, @"Filesystem", @"Filesystem consistency", mismatches, uncertain, @"Comparable APIs agree. Permission errors and dangling links are not contradictions.");

    char target[PATH_MAX];
    ssize_t n = readlink("/var/jb", target, sizeof(target) - 1); code = errno;
    if (n >= 0) target[n] = '\0';
    Add(rows, @"Symlinks", @"Rootless bootstrap symlink", n >= 0, n < 0 && code != EINVAL && SKPresenceFromCall(-1, code) == SKUnknown,
        n >= 0 ? [NSString stringWithFormat:@"/var/jb -> %s", target] : Error(code));
    char resolved[PATH_MAX];
    char *real = realpath("/var/jb", resolved); code = errno;
    Add(rows, @"Symlinks", @"Bootstrap path resolution", real != NULL, !real && SKPresenceFromCall(-1, code) == SKUnknown,
        real ? [NSString stringWithFormat:@"/var/jb resolves to %s", resolved] : Error(code));

    struct statfs fs; struct statvfs vfs;
    int a = statfs("/", &fs), ae = errno, b = statvfs("/", &vfs), be = errno;
    BOOL writable = (a == 0 && !(fs.f_flags & MNT_RDONLY)) || (b == 0 && !(vfs.f_flag & ST_RDONLY));
    Add(rows, @"Filesystem", @"Root mount writable flag", writable, a != 0 || b != 0,
        [NSString stringWithFormat:@"statfs: %@; statvfs: %@. This is mount metadata, not a successful write.",
            a == 0 ? [NSString stringWithFormat:@"type %s, flags 0x%x", fs.f_fstypename, fs.f_flags] : Error(ae),
            b == 0 ? [NSString stringWithFormat:@"flags 0x%lx", vfs.f_flag] : Error(be)]);
}

static void Apps(NSMutableArray *rows) {
    for (NSString *scheme in @[@"sileo", @"zbra", @"filza", @"dopamine"]) {
        __block BOOL found;
        void (^query)(void) = ^{ found = [[UIApplication sharedApplication] canOpenURL:[NSURL URLWithString:[scheme stringByAppendingString:@"://"]]]; };
        if ([NSThread isMainThread]) query(); else dispatch_sync(dispatch_get_main_queue(), query);
        Add(rows, @"App discovery", [scheme stringByAppendingString:@" URL handler"], found, NO, found ? @"Registered URL handler. An installed app alone does not prove an active jailbreak." : @"No handler reported by canOpenURL.");
    }
    NSMutableArray *hits = [NSMutableArray array], *errors = [NSMutableArray array];
    // ponytail: guarded private LaunchServices API; unavailable if iOS blocks or changes it.
    @try {
        Class workspaceClass = NSClassFromString(@"LSApplicationWorkspace");
        SEL shared = NSSelectorFromString(@"defaultWorkspace"), all = NSSelectorFromString(@"allApplications");
        id workspace = [workspaceClass respondsToSelector:shared] ? ((id (*)(id, SEL))objc_msgSend)(workspaceClass, shared) : nil;
        if (![workspace respondsToSelector:all]) [errors addObject:@"Application registration API unavailable."];
        else {
            id apps = ((id (*)(id, SEL))objc_msgSend)(workspace, all);
            if (![apps isKindOfClass:NSArray.class] || ![apps count]) [errors addObject:@"Application list empty or restricted; cannot infer absence."];
            else for (id app in apps) {
                SEL selector = NSSelectorFromString(@"bundleIdentifier");
                if (![app respondsToSelector:selector]) { [errors addObject:@"Bundle identifier API unavailable."]; break; }
                NSString *identifier = ((id (*)(id, SEL))objc_msgSend)(app, selector);
                if ([@[@"org.coolstar.SileoStore", @"xyz.willy.Zebra", @"com.tigisoftware.Filza", @"com.opa334.Dopamine", @"com.opa334.Dopamine.roothide"] containsObject:identifier]) [hits addObject:identifier];
            }
        }
    } @catch (NSException *exception) { [errors addObject:exception.reason ?: @"LaunchServices exception"]; }
    List(rows, @"App discovery", @"Application registration", hits, errors, @"No listed jailbreak bundle IDs reported. iOS may filter the list.");
}

static BOOL SuspiciousImage(NSString *path) {
    NSString *lower = path.lowercaseString;
    for (NSString *token in @[@"/var/jb/", @"/procursus/", @"/.jbroot-", @"/mobilesubstrate/", @"/tweakinject/", @"ellekit", @"systemhook", @"tweakloader", @"libhooker", @"libsubstitute", @"frida", @"cycript", @"sslkillswitch", @"abypass", @"liberty", @"shadow.dylib", @"roothide"])
        if ([lower containsString:token]) return YES;
    return NO;
}
static void Runtime(NSMutableArray *rows) {
    NSMutableArray *images = [NSMutableArray array], *instrumentation = [NSMutableArray array];
    uint32_t count = _dyld_image_count();
    for (uint32_t i = 1; i < count; i++) { // The main executable lives in /var/jb by design.
        const char *name = _dyld_get_image_name(i);
        if (!name) continue;
        NSString *path = @(name);
        if (SuspiciousImage(path)) [images addObject:path];
        if ([path.lowercaseString containsString:@"frida"] || [path.lowercaseString containsString:@"cycript"]) [instrumentation addObject:path];
    }
    List(rows, @"Loaded images", @"Injected Mach-O images", images, count ? @[] : @[@"dyld returned no images."], @"No known injection image names; main executable excluded.");
    List(rows, @"Instrumentation", @"Instrumentation modules", instrumentation, count ? @[] : @[@"dyld returned no images."], @"No Frida/Cycript image names observed.");
    NSMutableArray *classes = [NSMutableArray array];
    unsigned int classCount = 0;
    Class *list = objc_copyClassList(&classCount);
    for (unsigned int i = 0; i < classCount; i++) {
        NSString *name = @(class_getName(list[i]));
        if ([@[@"ShadowRuleset", @"FLEXManager", @"HBPreferences", @"Cycript", @"FridaGadget", @"ABypass", @"FlyJB", @"Liberty", @"Choicy"] containsObject:name]) {
            const char *origin = class_getImageName(list[i]);
            [classes addObject:[NSString stringWithFormat:@"%@ (%s)", name, origin ?: "unknown image"]];
        }
    }
    List(rows, @"Objective-C runtime", @"Registered classes", classes, list ? @[] : @[@"objc_copyClassList failed."], @"No listed tweak/instrumentation classes.");
    free(list);
    Class shadow = NSClassFromString(@"ShadowRuleset");
    BOOL selector = shadow && class_getInstanceMethod(shadow, NSSelectorFromString(@"internalDictionary"));
    Add(rows, @"Objective-C runtime", @"Shadow selector", selector, NO, selector ? @"ShadowRuleset implements internalDictionary." : @"Known Shadow class/selector pair not observed.");

    NSMutableArray *hooks = [NSMutableArray array], *errors = [NSMutableArray array];
    for (NSString *name in @[@"stat", @"lstat", @"access", @"open", @"sysctl", @"csops"]) {
        void *address = dlsym(RTLD_DEFAULT, name.UTF8String); Dl_info info = {0};
        if (!address || !dladdr(address, &info) || !info.dli_fname) [errors addObject:[name stringByAppendingString:@": symbol origin unavailable"]];
        else if (SuspiciousImage(@(info.dli_fname))) [hooks addObject:[NSString stringWithFormat:@"%@ -> %s", name, info.dli_fname]];
    }
    Method method = class_getInstanceMethod(NSFileManager.class, @selector(fileExistsAtPath:));
    Dl_info info = {0};
    if (!method || !dladdr((const void *)method_getImplementation(method), &info) || !info.dli_fname) [errors addObject:@"NSFileManager method origin unavailable."];
    else if (SuspiciousImage(@(info.dli_fname))) [hooks addObject:[NSString stringWithFormat:@"NSFileManager fileExistsAtPath: -> %s", info.dli_fname]];
    List(rows, @"Objective-C runtime", @"Function and method origins", hooks, errors, @"No sampled implementation resolves to a known injection image. Inline patches are not covered by dladdr.");
}

static void Behavior(NSMutableArray *rows) {
    for (NSString *directory in @[@"/private", @"/var/mobile", @"/var/jb"]) {
        NSString *path = [directory stringByAppendingPathComponent:[@".seeker-probe-" stringByAppendingString:NSUUID.UUID.UUIDString]];
        int fd = open(path.fileSystemRepresentation, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0600), code = errno;
        BOOL found = fd >= 0;
        NSString *detail = Error(code);
        if (found) {
            // Unlink our unique file immediately; the descriptor remains usable for the write probe.
            int removed = unlink(path.fileSystemRepresentation), removeError = errno;
            ssize_t written = write(fd, "s", 1); int writeError = errno;
            close(fd);
            detail = [NSString stringWithFormat:@"Created %@ outside the container. Write: %@. Cleanup: %@.", path,
                written == 1 ? @"1 byte" : Error(writeError), removed == 0 ? @"removed" : [NSString stringWithFormat:@"FAILED: %@; remove this exact file manually", Error(removeError)]];
        }
        BOOL expectedFailure = code == EACCES || code == EPERM || code == EROFS || code == ENOENT || code == ENOTDIR;
        Add(rows, @"Sandbox behavior", [@"Outside-container write: " stringByAppendingString:directory], found, !found && !expectedFailure, detail);
    }
    int fd = open("/var/mobile/Library/Safari", O_RDONLY | O_DIRECTORY | O_CLOEXEC), code = errno;
    if (fd >= 0) close(fd);
    Add(rows, @"Sandbox behavior", @"Restricted directory access", fd >= 0, fd < 0 && code != EACCES && code != EPERM && SKPresenceFromCall(-1, code) == SKUnknown,
        fd >= 0 ? @"Opened /var/mobile/Library/Safari. No contents were read." : Error(code));

    pid_t (*forkFunction)(void) = dlsym(RTLD_DEFAULT, "fork");
    if (!forkFunction) { Add(rows, @"Process behavior", @"fork()", NO, YES, @"fork symbol unavailable."); return; }
    pid_t child = forkFunction(); code = errno;
    if (child == 0) _exit(0); // Child must never return to Objective-C/UIKit after fork.
    NSString *detail = Error(code);
    if (child > 0) {
        int status = 0; pid_t waited = 0;
        for (int i = 0; i < 100; i++) {
            waited = waitpid(child, &status, WNOHANG);
            if (waited == child || (waited < 0 && errno != EINTR)) break;
            usleep(1000);
        }
        if (waited == 0 || (waited < 0 && errno == EINTR)) {
            kill(child, SIGKILL);
            do { waited = waitpid(child, &status, 0); } while (waited < 0 && errno == EINTR);
        }
        detail = [NSString stringWithFormat:@"Created child %d; %@. This reflects Seeker's launch context.", child, waited == child ? @"child reaped" : @"child no longer waitable"];
    }
    Add(rows, @"Process behavior", @"fork()", child > 0, child < 0 && code != EPERM && code != EACCES, detail);
}

static void DebugAndMemory(NSMutableArray *rows) {
    int mib[] = {CTL_KERN, KERN_PROC, KERN_PROC_PID, getpid()};
    struct kinfo_proc process = {0}; size_t length = sizeof(process);
    int rc = sysctl(mib, 4, &process, &length, NULL, 0), code = errno;
    BOOL valid = rc == 0 && length == sizeof(process);
    Add(rows, @"Debug state", @"Debugger attached (P_TRACED)", valid && (process.kp_proc.p_flag & P_TRACED), !valid,
        valid ? [NSString stringWithFormat:@"Process flags 0x%x; P_TRACED %@.", process.kp_proc.p_flag, (process.kp_proc.p_flag & P_TRACED) ? @"set" : @"unset"] : rc ? Error(code) : @"sysctl returned incomplete process data.");
    exception_mask_t masks[EXC_TYPES_COUNT]; mach_port_t ports[EXC_TYPES_COUNT];
    exception_behavior_t behaviors[EXC_TYPES_COUNT]; thread_state_flavor_t flavors[EXC_TYPES_COUNT];
    mach_msg_type_number_t count = EXC_TYPES_COUNT;
    kern_return_t kr = task_get_exception_ports(mach_task_self(), EXC_MASK_BREAKPOINT | EXC_MASK_BAD_ACCESS | EXC_MASK_SOFTWARE, masks, &count, ports, behaviors, flavors);
    NSMutableArray *handlers = [NSMutableArray array];
    if (kr == KERN_SUCCESS) for (mach_msg_type_number_t i = 0; i < count; i++) if (MACH_PORT_VALID(ports[i])) {
        [handlers addObject:[NSString stringWithFormat:@"Exception mask 0x%x, behavior %d (debuggers and crash reporters can register handlers).", masks[i], behaviors[i]]];
        mach_port_deallocate(mach_task_self(), ports[i]);
    }
    List(rows, @"Debug state", @"Task exception handlers", handlers, kr == KERN_SUCCESS ? @[] : @[@(mach_error_string(kr))], @"No sampled task exception handlers. Thread-specific handlers are not inspected.");

    NSMutableArray *regions = [NSMutableArray array];
    vm_address_t address = 0; natural_t depth = 0; unsigned int scanned = 0;
    // ponytail: inspect at most 8192 regions, RWX/JIT tags only; add image mapping if broader coverage is needed.
    for (; scanned < 8192; scanned++) {
        vm_size_t size = 0; struct vm_region_submap_info_64 region;
        mach_msg_type_number_t infoCount = VM_REGION_SUBMAP_INFO_COUNT_64;
        kr = vm_region_recurse_64(mach_task_self(), &address, &size, &depth, (vm_region_recurse_info_t)&region, &infoCount);
        if (kr != KERN_SUCCESS) break;
        if (region.is_submap) { depth++; continue; }
        if ((region.protection & VM_PROT_EXECUTE) && ((region.protection & VM_PROT_WRITE) || region.user_tag == VM_MEMORY_JAVASCRIPT_JIT_EXECUTABLE_ALLOCATOR))
            [regions addObject:[NSString stringWithFormat:@"0x%llx + 0x%llx, protection %d, tag %u. JIT can be legitimate.", (unsigned long long)address, (unsigned long long)size, region.protection, region.user_tag]];
        if (!size || address > UINT64_MAX - size) { kr = KERN_FAILURE; break; }
        address += size;
    }
    NSArray *errors = scanned == 8192 ? @[@"Region scan limit reached."] : (kr == KERN_INVALID_ADDRESS ? @[] : @[@(mach_error_string(kr))]);
    List(rows, @"Instrumentation", @"Executable memory", regions, errors, @"No writable executable or JavaScript JIT executable regions observed.");
}

static void Signing(NSMutableArray *rows) {
    // Values from Apple's XNU cs_blobs.h; query the current process only.
    int (*csopsFunction)(pid_t, unsigned int, void *, size_t) = dlsym(RTLD_DEFAULT, "csops");
    uint32_t flags = 0;
    int rc = csopsFunction ? csopsFunction(getpid(), 0, &flags, sizeof(flags)) : -1, code = errno;
    NSMutableArray *hits = [NSMutableArray array];
    if (rc == 0) {
        if (!(flags & 0x1)) [hits addObject:@"CS_VALID is unset."];
        if (flags & 0x2) [hits addObject:@"CS_ADHOC: expected for this Sileo package."];
        if (flags & 0x4) [hits addObject:@"CS_GET_TASK_ALLOW: debugger access allowed."];
        if (flags & 0x04000000) [hits addObject:@"CS_PLATFORM_BINARY: platform status."];
        if (flags & 0x10000000) [hits addObject:@"CS_DEBUGGED: code signing state relaxed by debugging."];
    }
    Add(rows, @"Code signing", @"Process signature flags", hits.count > 0, rc != 0, csopsFunction ? (rc == 0 ? [NSString stringWithFormat:@"Flags 0x%08x\n%@", flags, [hits componentsJoinedByString:@"\n"]] : Error(code)) : @"csops unavailable.");
    CFTypeRef (*createTask)(CFAllocatorRef) = dlsym(RTLD_DEFAULT, "SecTaskCreateFromSelf");
    CFTypeRef (*copyValue)(CFTypeRef, CFStringRef, CFErrorRef *) = dlsym(RTLD_DEFAULT, "SecTaskCopyValueForEntitlement");
    CFTypeRef task = createTask ? createTask(kCFAllocatorDefault) : NULL;
    NSMutableArray *entitlements = [NSMutableArray array], *errors = [NSMutableArray array];
    if (!task || !copyValue) [errors addObject:@"SecTask entitlement API unavailable."];
    else for (NSString *key in @[@"get-task-allow", @"task_for_pid-allow", @"platform-application", @"com.apple.private.security.no-container", @"com.apple.private.skip-library-validation", @"com.apple.security.cs.allow-jit", @"com.apple.private.security.container-required"]) {
        CFErrorRef error = NULL;
        CFTypeRef value = copyValue(task, (__bridge CFStringRef)key, &error);
        if (error) { [errors addObject:[NSString stringWithFormat:@"%@: %@", key, (__bridge NSError *)error]]; CFRelease(error); }
        BOOL disabledContainer = [key hasSuffix:@"container-required"];
        if (value && CFGetTypeID(value) == CFBooleanGetTypeID() && (CFBooleanGetValue(value) != disabledContainer))
            [entitlements addObject:[NSString stringWithFormat:@"%@ = %@", key, (__bridge id)value]];
        if (value) CFRelease(value);
    }
    if (task) CFRelease(task);
    List(rows, @"Code signing", @"Unexpected entitlements", entitlements, errors, @"No sampled privilege/debug entitlement enabled. Seeker requests a container.");
}

static void CodeIntegrity(NSMutableArray *rows) {
    NSError *error = nil;
    NSData *disk = [NSData dataWithContentsOfFile:NSBundle.mainBundle.executablePath options:0 error:&error];
    NSString *failure = error.localizedDescription ?: @"Unsupported or malformed main Mach-O file.";
    const struct mach_header *loaded = _dyld_get_image_header(0);
    if (disk.length >= sizeof(struct mach_header_64) && loaded && loaded->magic == MH_MAGIC_64) {
        const struct mach_header_64 *header = disk.bytes;
        size_t cursor = sizeof(*header);
        if (header->magic == MH_MAGIC_64 && header->sizeofcmds <= disk.length - cursor) {
            size_t end = cursor + header->sizeofcmds;
            for (uint32_t i = 0; i < header->ncmds && cursor + sizeof(struct load_command) <= end; i++) {
                const struct load_command *cmd = (const void *)((const char *)disk.bytes + cursor);
                if (cmd->cmdsize < sizeof(*cmd) || cmd->cmdsize > end - cursor) break;
                if (cmd->cmd == LC_SEGMENT_64 && cmd->cmdsize >= sizeof(struct segment_command_64)) {
                    const struct segment_command_64 *seg = (const void *)cmd;
                    if (seg->nsects > (cmd->cmdsize - sizeof(*seg)) / sizeof(struct section_64)) break;
                    const struct section_64 *sections = (const void *)(seg + 1);
                    for (uint32_t j = 0; j < seg->nsects; j++) {
                        const struct section_64 *section = &sections[j];
                        if (strncmp(section->segname, "__TEXT", 16) || strncmp(section->sectname, "__text", 16)) continue;
                        if (!section->size || section->size > 16 * 1024 * 1024 || section->offset > disk.length || section->size > disk.length - section->offset) break;
                        NSMutableData *memory = [NSMutableData dataWithLength:(NSUInteger)section->size];
                        vm_size_t copied = 0;
                        kern_return_t kr = vm_read_overwrite(mach_task_self(), section->addr + _dyld_get_image_vmaddr_slide(0), section->size, (vm_address_t)memory.mutableBytes, &copied);
                        BOOL valid = kr == KERN_SUCCESS && copied == section->size;
                        BOOL changed = valid && memcmp(memory.bytes, (const char *)disk.bytes + section->offset, memory.length) != 0;
                        Add(rows, @"Code signing", @"Main executable code changed", changed, !valid, valid ? (changed ? @"In-memory __TEXT,__text differs from disk. Breakpoints or hooks can change it." : @"In-memory __TEXT,__text matches disk. This does not authenticate the disk copy or other images.") : (kr == KERN_SUCCESS ? @"Memory read was incomplete." : @(mach_error_string(kr))));
                        return;
                    }
                }
                cursor += cmd->cmdsize;
            }
        }
    }
    Add(rows, @"Code signing", @"Main executable code changed", NO, YES, failure);
}

static void EnvironmentAndIPC(NSMutableArray *rows) {
    NSMutableArray *variables = [NSMutableArray array];
    for (NSString *name in @[@"DYLD_INSERT_LIBRARIES", @"DYLD_LIBRARY_PATH", @"_MSSafeMode", @"_SafeMode", @"JB_ROOT_PATH", @"JBROOT", @"LIBHOOKER_CONFIG", @"FRIDA_GADGET_CONFIG"]) {
        const char *value = getenv(name.UTF8String);
        if (value) [variables addObject:[NSString stringWithFormat:@"%@=%s", name, value]];
    }
    List(rows, @"Environment and IPC", @"Injection environment", variables, @[], @"No listed variables present; injectors can remove them.");
    for (NSNumber *port in @[@27042, @27043, @22]) {
        int fd = socket(AF_INET, SOCK_STREAM, 0), code = errno;
        BOOL connected = NO;
        if (fd >= 0) {
            struct sockaddr_in address = {.sin_len = sizeof(address), .sin_family = AF_INET, .sin_port = htons(port.unsignedShortValue), .sin_addr.s_addr = htonl(INADDR_LOOPBACK)};
            if (fcntl(fd, F_SETFL, O_NONBLOCK) == 0) {
                int rc = connect(fd, (struct sockaddr *)&address, sizeof(address)); code = rc == 0 ? 0 : errno;
                if (rc < 0 && code == EINPROGRESS) {
                    struct pollfd polling = {.fd = fd, .events = POLLOUT};
                    rc = poll(&polling, 1, 150);
                    if (rc > 0) { socklen_t size = sizeof(code); if (getsockopt(fd, SOL_SOCKET, SO_ERROR, &code, &size) < 0) code = errno; }
                    else code = rc == 0 ? ETIMEDOUT : errno;
                }
                connected = code == 0;
            } else code = errno;
            close(fd);
        }
        Add(rows, port.intValue == 22 ? @"Environment and IPC" : @"Instrumentation", [NSString stringWithFormat:@"Loopback TCP %@", port], connected, !connected && code != ECONNREFUSED,
            connected ? @"TCP connection accepted on 127.0.0.1. No payload sent. Port alone does not identify the service." : Error(code));
    }
    // RocketBootstrap source defines these names. Dopamine uses launchd directly, not a named jailbreakd service.
    for (NSString *service in @[@"com.rpetrich.rocketbootstrapd", @"cy:rbs"]) {
        mach_port_t port = MACH_PORT_NULL;
        kern_return_t kr = bootstrap_look_up(bootstrap_port, service.UTF8String, &port);
        BOOL found = kr == KERN_SUCCESS && MACH_PORT_VALID(port);
        if (MACH_PORT_VALID(port)) mach_port_deallocate(mach_task_self(), port);
        Add(rows, @"Environment and IPC", [@"Mach service: " stringByAppendingString:service], found, !found,
            found ? @"Lookup returned a send right. No messages sent." : [NSString stringWithFormat:@"Lookup returned %d. Missing and sandbox-hidden services cannot be distinguished.", kr]);
    }
}

NSArray<NSDictionary<NSString *, NSString *> *> *SKRunChecks(void) {
    NSMutableArray *rows = [NSMutableArray array];
    Filesystem(rows);
    Apps(rows);
    Runtime(rows);
    Behavior(rows);
    DebugAndMemory(rows);
    Signing(rows);
    CodeIntegrity(rows);
    EnvironmentAndIPC(rows);
    return rows;
}
