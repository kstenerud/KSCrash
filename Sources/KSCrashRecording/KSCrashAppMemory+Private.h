#import <Foundation/Foundation.h>
#import "KSCrashAppMemory.h"

NS_ASSUME_NONNULL_BEGIN

/**
 * Internal and for tests.
 */
@interface KSCrashAppMemory ()
- (instancetype)initWithFootprint:(uint64_t)footprint
                        remaining:(uint64_t)remaining
                         pressure:(KSCrashAppMemoryState)pressure
                  systemRemaining:(uint64_t)systemRemaining
                      systemLimit:(uint64_t)systemLimit NS_DESIGNATED_INITIALIZER;
@end

// Nullable so tests can simulate a failed sample (task_info error).
typedef KSCrashAppMemory *_Nullable (^KSCrashAppMemoryProvider)(void);
FOUNDATION_EXPORT void testsupport_KSCrashAppMemorySetProvider(KSCrashAppMemoryProvider _Nullable provider);

NS_ASSUME_NONNULL_END
