#import <Foundation/Foundation.h>

// Read once before hooks are installed. No cfprefsd/container redirection involved.
static NSString *const HSConfigPath = @"/var/jb/var/mobile/Library/Hider/apps.plist";

static BOOL HSProtectedApp(NSString *identifier) {
    return [identifier isEqualToString:@"com.apple.Preferences"] ||
           [identifier isEqualToString:@"com.apple.springboard"];
}

static NSSet<NSString *> *HSReadApps(NSError **error) {
    NSData *data = [NSData dataWithContentsOfFile:HSConfigPath options:0 error:error];
    if (!data) return nil;
    id value = [NSPropertyListSerialization propertyListWithData:data options:NSPropertyListImmutable format:NULL error:error];
    if (![value isKindOfClass:NSArray.class]) {
        if (error && !*error) *error = [NSError errorWithDomain:NSCocoaErrorDomain code:NSPropertyListReadCorruptError userInfo:nil];
        return nil;
    }
    NSMutableSet *apps = [NSMutableSet set];
    for (id identifier in value) {
        if (![identifier isKindOfClass:NSString.class] || ![identifier length] || [identifier length] > 255) {
            if (error) *error = [NSError errorWithDomain:NSCocoaErrorDomain code:NSPropertyListReadCorruptError userInfo:nil];
            return nil;
        }
        if (!HSProtectedApp(identifier)) [apps addObject:identifier];
    }
    return apps;
}
