#import <Foundation/Foundation.h>

// Rows have category, name, state (FIRED / NOT OBSERVED / UNAVAILABLE), evidence.
NSArray<NSDictionary<NSString *, NSString *> *> *SKRunChecks(void);
