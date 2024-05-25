#import "KSCrashAppStateTracker.h"

NS_ASSUME_NONNULL_BEGIN

@interface KSCrashAppStateTracker ()

- (void)_setTransitionState:(KSCrashAppTransitionState)transitionState;

@property (nonatomic, assign) BOOL proxied;

@end

NS_ASSUME_NONNULL_END
