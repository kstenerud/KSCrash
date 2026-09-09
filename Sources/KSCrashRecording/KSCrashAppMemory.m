#import "KSCrashAppMemory.h"

#import "KSCrashAppMemory+Private.h"

NS_ASSUME_NONNULL_BEGIN

/** Derive a state from a used value and its enclosing limit.
 *
 *  `baselineBasisPoints` (0-10000) shifts the 25/50/75/95 ladder up the range,
 *  treating [0, baseline] as a logical zero that always reports normal. Headroom
 *  passes 8000 (0.80) because a ratio against physical memory is dominated by
 *  wired kernel pages and always-on system overhead; only the top ~20% of the
 *  range is meaningful headroom, putting the headroom band edges at 0.85, 0.90,
 *  0.95, and 0.99 of physical memory. Retuning the shared ladder moves those
 *  bands too.
 *
 *  Thresholds are built in integer basis points so band boundaries stay exact;
 *  summing double fractions instead would put values like 850/1000 on the wrong
 *  side of the 0.85 edge.
 */
static KSCrashAppMemoryState StateFromUsage(uint64_t used, uint64_t limit, uint64_t baselineBasisPoints)
{
    if (limit == 0) {
        return KSCrashAppMemoryStateNormal;
    }
    baselineBasisPoints = MIN(baselineBasisPoints, 10000);
    uint64_t scale = 10000 - baselineBasisPoints;
    double usedRatio = (double)used / (double)limit;

#define KSCRASH_STATE_THRESHOLD(fractionBasisPoints) \
    ((double)(baselineBasisPoints + (fractionBasisPoints) * scale / 10000) / 10000.0)

    return usedRatio < KSCRASH_STATE_THRESHOLD(2500)   ? KSCrashAppMemoryStateNormal
           : usedRatio < KSCRASH_STATE_THRESHOLD(5000) ? KSCrashAppMemoryStateWarn
           : usedRatio < KSCRASH_STATE_THRESHOLD(7500) ? KSCrashAppMemoryStateUrgent
           : usedRatio < KSCRASH_STATE_THRESHOLD(9500) ? KSCrashAppMemoryStateCritical
                                                       : KSCrashAppMemoryStateTerminal;

#undef KSCRASH_STATE_THRESHOLD
}

@implementation KSCrashAppMemory

- (instancetype)initWithFootprint:(uint64_t)footprint
                        remaining:(uint64_t)remaining
                         pressure:(KSCrashAppMemoryState)pressure
                  systemRemaining:(uint64_t)systemRemaining
                      systemLimit:(uint64_t)systemLimit
{
    if ((self = [super init])) {
        _footprint = footprint;
        _remaining = remaining;
        _pressure = pressure;
        _systemRemaining = systemRemaining;
        _systemLimit = systemLimit;
    }
    return self;
}

- (BOOL)isEqual:(id)object
{
    if (![object isKindOfClass:self.class]) {
        return NO;
    }
    KSCrashAppMemory *comp = (KSCrashAppMemory *)object;
    return comp.footprint == self.footprint && comp.remaining == self.remaining && comp.pressure == self.pressure &&
           comp.systemRemaining == self.systemRemaining && comp.systemLimit == self.systemLimit;
}

- (uint64_t)limit
{
    return _footprint + _remaining;
}

- (KSCrashAppMemoryState)level
{
    return StateFromUsage(self.footprint, self.limit, 0);
}

- (KSCrashAppMemoryState)headroom
{
    uint64_t used = _systemLimit > _systemRemaining ? _systemLimit - _systemRemaining : 0;
    return StateFromUsage(used, _systemLimit, 8000);
}

- (BOOL)isOutOfMemory
{
    return self.level >= KSCrashAppMemoryStateCritical || self.pressure >= KSCrashAppMemoryStateCritical;
}

@end

const char *KSCrashAppMemoryStateToString(KSCrashAppMemoryState state)
{
    switch (state) {
        case KSCrashAppMemoryStateNormal:
            return "normal";
        case KSCrashAppMemoryStateWarn:
            return "warn";
        case KSCrashAppMemoryStateUrgent:
            return "urgent";
        case KSCrashAppMemoryStateCritical:
            return "critical";
        case KSCrashAppMemoryStateTerminal:
            return "terminal";
        default:
            // Raw sidecar bytes from disk land here, so an out-of-range value
            // must map to a string; asserting would crash-loop report delivery.
            return "unknown";
    }
}

KSCrashAppMemoryState KSCrashAppMemoryStateFromString(NSString *const string)
{
    if ([string isEqualToString:@"normal"]) {
        return KSCrashAppMemoryStateNormal;
    }

    if ([string isEqualToString:@"warn"]) {
        return KSCrashAppMemoryStateWarn;
    }

    if ([string isEqualToString:@"urgent"]) {
        return KSCrashAppMemoryStateUrgent;
    }

    if ([string isEqualToString:@"critical"]) {
        return KSCrashAppMemoryStateCritical;
    }

    if ([string isEqualToString:@"terminal"]) {
        return KSCrashAppMemoryStateTerminal;
    }

    return KSCrashAppMemoryStateNormal;
}

NSNotificationName const KSCrashAppMemoryLevelChangedNotification = @"KSCrashAppMemoryLevelChangedNotification";
NSNotificationName const KSCrashAppMemoryPressureChangedNotification = @"KSCrashAppMemoryPressureChangedNotification";
NSNotificationName const KSCrashAppMemoryHeadroomChangedNotification = @"KSCrashAppMemoryHeadroomChangedNotification";
NSString *const KSCrashAppMemoryNewValueKey = @"KSCrashAppMemoryNewValueKey";
NSString *const KSCrashAppMemoryOldValueKey = @"KSCrashAppMemoryOldValueKey";

NS_ASSUME_NONNULL_END
