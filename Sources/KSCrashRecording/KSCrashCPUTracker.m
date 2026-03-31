//
//  KSCrashCPUTracker.m
//
//  Created by Alexander Cohen on 2026-03-29.
//
//  Copyright (c) 2012 Karl Stenerud. All rights reserved.
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall remain in place
// in this source code.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
// THE SOFTWARE.
//

#import "KSCrashCPUTracker.h"

#import <os/lock.h>
#import <unistd.h>

#if __has_include(<libproc.h>)
#import <libproc.h>
#else
#define PROC_PIDTASKINFO 4
struct proc_taskinfo {
    uint64_t pti_virtual_size;
    uint64_t pti_resident_size;
    uint64_t pti_total_user;
    uint64_t pti_total_system;
    uint64_t pti_threads_user;
    uint64_t pti_threads_system;
    int32_t pti_policy;
    int32_t pti_faults;
    int32_t pti_pageins;
    int32_t pti_cow_faults;
    int32_t pti_messages_sent;
    int32_t pti_messages_received;
    int32_t pti_syscalls_mach;
    int32_t pti_syscalls_unix;
    int32_t pti_csw;
    int32_t pti_threadnum;
    int32_t pti_numrunning;
    int32_t pti_priority;
};
extern int proc_pidinfo(int pid, int flavor, uint64_t arg, void *buffer, int buffersize);
#endif

#import "KSDate.h"
#import "KSSysCtl.h"

// ============================================================================
#pragma mark - CPU State String -
// ============================================================================

const char *KSCrashCPUStateToString(KSCrashCPUState state)
{
    switch (state) {
        case KSCrashCPUStateNormal:
            return "normal";
        case KSCrashCPUStateWarning:
            return "warning";
        case KSCrashCPUStateCritical:
            return "critical";
        default:
            return "normal";
    }
}

// ============================================================================
#pragma mark - Constants -
// ============================================================================

static const NSTimeInterval kPollingInterval = 5.0;

// Ring buffer holds cumulative CPU-time snapshots for sliding-window
// averages. 48 entries = 47 intervals * 5s ≈ 235s, giving comfortable
// headroom beyond the 180s warning window even if a poll fires slightly late.
static const NSUInteger kRingBufferCapacity = 48;

// Thresholds derived from Apple MetricKit CPU exception diagnostics.
// These are fractions of total CPU capacity (1.0 = all cores at 100%).
static const double kWarningThreshold = 0.50;
static const double kCriticalThreshold = 0.80;
static const NSTimeInterval kWarningWindow = 180.0;
static const NSTimeInterval kCriticalWindow = 60.0;

// ============================================================================
#pragma mark - KSCrashCPU -
// ============================================================================

@interface KSCrashCPU ()
- (instancetype)initWithState:(KSCrashCPUState)state
                    usageUser:(uint16_t)usageUser
                  usageSystem:(uint16_t)usageSystem
                  threadCount:(uint16_t)threadCount
         averageUsageInWindow:(double)averageUsageInWindow
              cpuTimeInWindow:(NSTimeInterval)cpuTimeInWindow
             wallTimeInWindow:(NSTimeInterval)wallTimeInWindow NS_DESIGNATED_INITIALIZER;
@end

@implementation KSCrashCPU

- (instancetype)initWithState:(KSCrashCPUState)state
                    usageUser:(uint16_t)usageUser
                  usageSystem:(uint16_t)usageSystem
                  threadCount:(uint16_t)threadCount
         averageUsageInWindow:(double)averageUsageInWindow
              cpuTimeInWindow:(NSTimeInterval)cpuTimeInWindow
             wallTimeInWindow:(NSTimeInterval)wallTimeInWindow
{
    if ((self = [super init])) {
        _state = state;
        _usageUser = usageUser;
        _usageSystem = usageSystem;
        _threadCount = threadCount;
        _averageUsageInWindow = averageUsageInWindow;
        _cpuTimeInWindow = cpuTimeInWindow;
        _wallTimeInWindow = wallTimeInWindow;
    }
    return self;
}

- (id)copyWithZone:(__unused NSZone *)zone
{
    // All properties are readonly value types, so self is already immutable.
    return self;
}

@end

// ============================================================================
#pragma mark - Ring Buffer Entry -
// ============================================================================

typedef struct {
    uint64_t wallNs;     // monotonic (continuous) nanoseconds
    uint64_t cpuTimeNs;  // cumulative user + system CPU nanoseconds
} KSCPURingSample;

// ============================================================================
#pragma mark - KSCrashCPUTracker -
// ============================================================================

@interface KSCrashCPUTracker () {
    dispatch_queue_t _queue;
    dispatch_source_t _timer;

    os_unfair_lock _lock;
    KSCrashCPUState _state;
    KSCrashCPU *_lastCPU;
    NSPointerArray *_observers;

    // Ring buffer and per-interval state — accessed only from _queue.
    KSCPURingSample _ring[48];  // kRingBufferCapacity
    NSUInteger _ringHead;
    NSUInteger _ringCount;

    uint64_t _prevUserNs;
    uint64_t _prevSystemNs;
    uint64_t _prevWallNs;

    uint8_t _coreCount;
}
@end

@implementation KSCrashCPUTracker

+ (instancetype)sharedInstance
{
    static KSCrashCPUTracker *sTracker;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sTracker = [[KSCrashCPUTracker alloc] init];
        [sTracker _start];
    });
    return sTracker;
}

- (instancetype)init
{
    if ((self = [super init])) {
        _lock = OS_UNFAIR_LOCK_INIT;
        _queue = dispatch_queue_create_with_target("com.kscrash.cpu.heartbeat", DISPATCH_QUEUE_SERIAL,
                                                   dispatch_get_global_queue(QOS_CLASS_UTILITY, 0));
        _state = KSCrashCPUStateNormal;
        _observers = [NSPointerArray weakObjectsPointerArray];

        int32_t count = kssysctl_int32ForName("hw.activecpu");
        _coreCount = (count > 0) ? (uint8_t)(count > 255 ? 255 : count) : 1;
    }
    return self;
}

- (id)addObserverWithBlock:(KSCrashCPUTrackerObserverBlock)block
{
    if (!block) {
        return nil;
    }
    id heapBlock = [block copy];
    os_unfair_lock_lock(&_lock);
    [_observers addPointer:(__bridge void *_Nullable)(heapBlock)];
    os_unfair_lock_unlock(&_lock);
    return heapBlock;
}

- (KSCrashCPUState)state
{
    os_unfair_lock_lock(&_lock);
    KSCrashCPUState s = _state;
    os_unfair_lock_unlock(&_lock);
    return s;
}

- (KSCrashCPU *)currentCPU
{
    os_unfair_lock_lock(&_lock);
    KSCrashCPU *snapshot = [_lastCPU copy];
    os_unfair_lock_unlock(&_lock);
    return snapshot;
}

// ============================================================================
#pragma mark - Timer -
// ============================================================================

- (void)_start
{
    _timer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, _queue);
    __weak __typeof(self) weakMe = self;
    dispatch_source_set_event_handler(_timer, ^{
        [weakMe _tick];
    });
    dispatch_source_set_timer(_timer, dispatch_time(DISPATCH_TIME_NOW, 0), (uint64_t)(kPollingInterval * NSEC_PER_SEC),
                              NSEC_PER_SEC);
    dispatch_activate(_timer);
}

// ============================================================================
#pragma mark - Polling (runs on _queue) -
// ============================================================================

/** Polls proc_pidinfo, updates the ring buffer, computes window averages,
 *  and returns an immutable snapshot. Must be called on _queue. */
- (nullable KSCrashCPU *)_poll
{
    struct proc_taskinfo taskInfo = { 0 };
    int size = proc_pidinfo(getpid(), PROC_PIDTASKINFO, 0, &taskInfo, sizeof(taskInfo));
    if (size != (int)sizeof(taskInfo)) {
        return nil;
    }

    uint64_t nowNs = ksdate_continuousNanoseconds();
    uint64_t cumulativeCpuNs = taskInfo.pti_total_user + taskInfo.pti_total_system;

    // --- Per-interval delta (instantaneous usage since last poll) ---
    uint16_t userUsage = 0;
    uint16_t systemUsage = 0;
    if (_prevWallNs > 0 && nowNs > _prevWallNs) {
        uint64_t wallDelta = nowNs - _prevWallNs;
        uint64_t userDelta = taskInfo.pti_total_user - _prevUserNs;
        uint64_t systemDelta = taskInfo.pti_total_system - _prevSystemNs;
        uint64_t userPermil = (userDelta * 1000) / wallDelta;
        uint64_t systemPermil = (systemDelta * 1000) / wallDelta;
        userUsage = (uint16_t)(userPermil > UINT16_MAX ? UINT16_MAX : userPermil);
        systemUsage = (uint16_t)(systemPermil > UINT16_MAX ? UINT16_MAX : systemPermil);
    }
    _prevUserNs = taskInfo.pti_total_user;
    _prevSystemNs = taskInfo.pti_total_system;
    _prevWallNs = nowNs;

    uint16_t threadCount = (uint16_t)(taskInfo.pti_threadnum > UINT16_MAX ? UINT16_MAX : taskInfo.pti_threadnum);

    // --- Ring buffer update ---
    _ring[_ringHead] = (KSCPURingSample) { .wallNs = nowNs, .cpuTimeNs = cumulativeCpuNs };
    _ringHead = (_ringHead + 1) % kRingBufferCapacity;
    if (_ringCount < kRingBufferCapacity) {
        _ringCount++;
    }

    // --- Sliding window averages ---
    KSCrashCPUState newState = KSCrashCPUStateNormal;
    double averageUsage = 0;
    NSTimeInterval cpuTimeInWindow = 0;
    NSTimeInterval wallTimeInWindow = 0;

    if (_ringCount >= 2) {
        NSUInteger newest = (_ringHead + kRingBufferCapacity - 1) % kRingBufferCapacity;
        KSCPURingSample newestSample = _ring[newest];

        double criticalAvg = [self _averageForWindow:kCriticalWindow newest:newestSample];
        double warningAvg = [self _averageForWindow:kWarningWindow newest:newestSample];

        if (criticalAvg >= kCriticalThreshold) {
            newState = KSCrashCPUStateCritical;
            KSCPURingSample oldest = [self _oldestSampleForWindow:kCriticalWindow];
            averageUsage = criticalAvg;
            cpuTimeInWindow = (double)(newestSample.cpuTimeNs - oldest.cpuTimeNs) / 1e9;
            wallTimeInWindow = (double)(newestSample.wallNs - oldest.wallNs) / 1e9;
        } else if (warningAvg >= kWarningThreshold) {
            newState = KSCrashCPUStateWarning;
            KSCPURingSample oldest = [self _oldestSampleForWindow:kWarningWindow];
            averageUsage = warningAvg;
            cpuTimeInWindow = (double)(newestSample.cpuTimeNs - oldest.cpuTimeNs) / 1e9;
            wallTimeInWindow = (double)(newestSample.wallNs - oldest.wallNs) / 1e9;
        }
    }

    return [[KSCrashCPU alloc] initWithState:newState
                                   usageUser:userUsage
                                 usageSystem:systemUsage
                                 threadCount:threadCount
                        averageUsageInWindow:averageUsage
                             cpuTimeInWindow:cpuTimeInWindow
                            wallTimeInWindow:wallTimeInWindow];
}

/** Computes the average CPU fraction of total capacity over the given window.
 *  Returns 0 if the ring doesn't cover at least the full window duration.
 *  Result is normalized by core count: 1.0 = 100% of all cores. */
- (double)_averageForWindow:(NSTimeInterval)windowSeconds newest:(KSCPURingSample)newest
{
    KSCPURingSample oldest = [self _oldestSampleForWindow:windowSeconds];
    if (oldest.wallNs == 0 || oldest.wallNs == newest.wallNs) {
        return 0;
    }
    double wallDelta = (double)(newest.wallNs - oldest.wallNs);
    // Require the ring to actually span the full window before classifying.
    if (wallDelta < windowSeconds * 1e9) {
        return 0;
    }
    double cpuDelta = (double)(newest.cpuTimeNs - oldest.cpuTimeNs);
    // cpuDelta/wallDelta is fraction of one core; divide by core count
    // to get fraction of total capacity.
    return (cpuDelta / wallDelta) / _coreCount;
}

/** Finds the oldest ring sample that is at least windowSeconds old,
 *  or the oldest available sample if the ring hasn't filled that far. */
- (KSCPURingSample)_oldestSampleForWindow:(NSTimeInterval)windowSeconds
{
    NSUInteger newest = (_ringHead + kRingBufferCapacity - 1) % kRingBufferCapacity;
    uint64_t cutoffNs = _ring[newest].wallNs - (uint64_t)(windowSeconds * 1e9);

    NSUInteger oldestIdx = (_ringHead + kRingBufferCapacity - _ringCount) % kRingBufferCapacity;
    KSCPURingSample best = _ring[oldestIdx];

    for (NSUInteger i = 0; i < _ringCount; i++) {
        NSUInteger idx = (oldestIdx + i) % kRingBufferCapacity;
        if (_ring[idx].wallNs <= cutoffNs) {
            best = _ring[idx];
        } else {
            break;
        }
    }
    return best;
}

/** Timer callback — poll, update state, notify observers. */
- (void)_tick
{
    KSCrashCPU *cpu = [self _poll];
    if (!cpu) return;

    NSArray<KSCrashCPUTrackerObserverBlock> *observers = nil;
    KSCrashCPUState oldState;
    {
        os_unfair_lock_lock(&_lock);
        oldState = _state;
        _state = cpu.state;
        _lastCPU = cpu;
        [_observers compact];
        observers = [_observers allObjects];
        os_unfair_lock_unlock(&_lock);
    }

    KSCrashCPUTrackerChangeType changes = KSCrashCPUTrackerChangeTypeUsage;
    if (cpu.state != oldState) {
        changes |= KSCrashCPUTrackerChangeTypeState;
    }

    for (KSCrashCPUTrackerObserverBlock obs in observers) {
        obs(cpu, changes);
    }
}

@end
