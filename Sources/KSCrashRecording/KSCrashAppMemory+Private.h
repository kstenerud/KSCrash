#import <Foundation/Foundation.h>
#import "KSCrashAppMemory.h"

NS_ASSUME_NONNULL_BEGIN

/**
 * Internal and for tests.
 */
@interface KSCrashAppMemory ()
- (instancetype)initWithFootprint:(uint64_t)footprint
                        remaining:(uint64_t)remaining
                         pressure:(KSCrashAppMemoryState)pressure NS_DESIGNATED_INITIALIZER;
@end

typedef KSCrashAppMemory *_Nonnull (^KSCrashAppMemoryProvider)(void);
FOUNDATION_EXPORT void testsupport_KSCrashAppMemorySetProvider(KSCrashAppMemoryProvider _Nullable provider);

NS_ASSUME_NONNULL_END
