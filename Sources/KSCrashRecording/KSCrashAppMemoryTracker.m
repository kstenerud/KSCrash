#import "KSCrashAppMemoryTracker.h"

#import "KSCrashAppMemory+Private.h"
#import "KSSystemCapabilities.h"

#import <mach/mach.h>
#import <mach/task.h>
#import <os/lock.h>
#import <stdatomic.h>

#if KSCRASH_HAS_UIAPPLICATION
#import <UIKit/UIKit.h>
#endif

/**
 The memory tracker takes care of centralizing the knowledge around memory.
 It does the following:

 1- Wraps memory pressure. This is more useful than `didReceiveMemoryWarning`
 as it vends different levels of pressure caused by the app as well as the rest of the OS.

 2- Vends a memory level. This is pretty novel. It vends levels of where the app is wihtin
 the memory limit.

 Some useful info.

 Memory Pressure is mostly useful when the app is in the background.
 It helps understand how much `pressure` is on the app due to external concerns. Using
 this data, we can make informed decisions around the reasons the app might have been
 terminated.

 Memory Level is useful in the foreground as well as background. It indicates where the app is
 within its memory limit. That limit being calculated by the addition of `remaining` and
 `footprint`. Using this data, we can also make informed decisions around foreground and background
 memory terminations, aka. OOMs.

 See: https://github.com/naftaly/Footprint
 */

static os_unfair_lock gMemoryProviderLock = OS_UNFAIR_LOCK_INIT;
static KSCrashAppMemoryProvider gMemoryProvider = nil;

static KSCrashAppMemoryProvider KSCrashAppMemoryGetProvider(void)
{
    os_unfair_lock_lock(&gMemoryProviderLock);
    KSCrashAppMemoryProvider provider = gMemoryProvider;
    os_unfair_lock_unlock(&gMemoryProviderLock);
    return provider;
}

FOUNDATION_EXPORT void testsupport_KSCrashAppMemorySetProvider(KSCrashAppMemoryProvider provider)
{
    os_unfair_lock_lock(&gMemoryProviderLock);
    gMemoryProvider = [provider copy];
    os_unfair_lock_unlock(&gMemoryProviderLock);
}

@interface KSCrashAppMemoryTracker () {
    dispatch_queue_t _heartbeatQueue;
    dispatch_source_t _pressureSource;
    dispatch_source_t _limitSource;

    os_unfair_lock _lock;
    uint64_t _footprint;
    uint64_t _systemRemaining;
    KSCrashAppMemoryState _pressure;
    KSCrashAppMemoryState _level;
    KSCrashAppMemoryState _headroom;

    // weak objects are `KSCrashAppMemoryTrackerObserverBlock`'s
    NSPointerArray *_observers;
}
@end

static KSCrashAppMemoryState StateFromPressureFlags(dispatch_source_memorypressure_flags_t flags)
{
    switch (flags) {
        case DISPATCH_MEMORYPRESSURE_WARN:
            return KSCrashAppMemoryStateWarn;
        case DISPATCH_MEMORYPRESSURE_CRITICAL:
            return KSCrashAppMemoryStateCritical;
        default:
            return KSCrashAppMemoryStateNormal;
    }
}

@implementation KSCrashAppMemoryTracker

+ (instancetype)sharedInstance
{
    static KSCrashAppMemoryTracker *sTracker;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sTracker = [[KSCrashAppMemoryTracker alloc] init];
        [sTracker start];
    });
    return sTracker;
}

- (instancetype)init
{
    if ((self = [super init])) {
        _lock = OS_UNFAIR_LOCK_INIT;
        _heartbeatQueue = dispatch_queue_create_with_target("com.kscrash.memory.heartbeat", DISPATCH_QUEUE_SERIAL,
                                                            dispatch_get_global_queue(QOS_CLASS_DEFAULT, 0));
        _level = KSCrashAppMemoryStateNormal;
        _pressure = KSCrashAppMemoryStateNormal;
        _headroom = KSCrashAppMemoryStateNormal;
        _observers = [NSPointerArray weakObjectsPointerArray];
    }
    return self;
}

- (void)dealloc
{
    [self stop];
}

- (id)addObserverWithBlock:(KSCrashAppMemoryTrackerObserverBlock)block
{
    if (!block) {
        return nil;
    }
    // Blocks are often on the stack so copy it
    // to make sure we have a copy on the heap
    // that will last for as long as the caller holds onto it.
    id heapBlock = [block copy];
    os_unfair_lock_lock(&_lock);
    [_observers addPointer:(__bridge void *_Nullable)(heapBlock)];
    os_unfair_lock_unlock(&_lock);
    return heapBlock;
}

- (void)start
{
    // kill the old ones
    if (_pressureSource || _limitSource) {
        [self stop];
    }

    // memory pressure
    uintptr_t mask = DISPATCH_MEMORYPRESSURE_NORMAL | DISPATCH_MEMORYPRESSURE_WARN | DISPATCH_MEMORYPRESSURE_CRITICAL;
    _pressureSource = dispatch_source_create(DISPATCH_SOURCE_TYPE_MEMORYPRESSURE, 0, mask, _heartbeatQueue);

    __weak __typeof(self) weakMe = self;

    // Both handlers read pressure from this captured source, never from
    // _pressureSource, which -stop and -start replace on another thread. The
    // capture keeps the source alive until -stop cancels it, which releases
    // the handlers.
    dispatch_source_t pressureSource = _pressureSource;
    dispatch_source_set_event_handler(pressureSource, ^{
        [weakMe _heartbeat:YES pressure:StateFromPressureFlags(dispatch_source_get_data(pressureSource))];
    });
    dispatch_activate(_pressureSource);

    // memory limit (level)
    _limitSource = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, _heartbeatQueue);
    dispatch_source_set_event_handler(_limitSource, ^{
        [weakMe _heartbeat:YES pressure:StateFromPressureFlags(dispatch_source_get_data(pressureSource))];
    });
    dispatch_source_set_timer(_limitSource, dispatch_time(DISPATCH_TIME_NOW, 0), NSEC_PER_SEC, NSEC_PER_SEC / 10);
    dispatch_activate(_limitSource);

#if KSCRASH_HAS_UIAPPLICATION
    // We won't always hit this depending on how the system is setup in the app,
    // but at least we can try.
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(_appDidFinishLaunching)
                                                 name:UIApplicationDidFinishLaunchingNotification
                                               object:nil];
#endif
    NSArray<KSCrashAppMemoryTrackerObserverBlock> *observers = nil;
    {
        os_unfair_lock_lock(&_lock);
        [_observers compact];
        observers = [_observers allObjects];
        os_unfair_lock_unlock(&_lock);
    }
    // Keep this initial callback synchronous on the caller's thread and outside
    // _lock so observers can re-enter the tracker. It may interleave with a
    // heartbeat; brief startup staleness is acceptable for diagnostic snapshots.
    // Avoid queue hops or generation tracking solely to order this delivery.
    // A sample costs kernel round trips, so skip it when nobody would get it.
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
    BOOL hasDelegate = self.delegate != nil;
#pragma clang diagnostic pop
    if (observers.count == 0 && !hasDelegate) {
        return;
    }
    [self _handleMemoryChange:[self currentAppMemory] type:KSCrashAppMemoryTrackerChangeTypeNone observers:observers];
}

#if KSCRASH_HAS_UIAPPLICATION
- (void)_appDidFinishLaunching
{
    NSArray<KSCrashAppMemoryTrackerObserverBlock> *observers = nil;
    {
        os_unfair_lock_lock(&_lock);
        [_observers compact];
        observers = [_observers allObjects];
        os_unfair_lock_unlock(&_lock);
    }
    [self _handleMemoryChange:[self currentAppMemory] type:KSCrashAppMemoryTrackerChangeTypeNone observers:observers];
}
#endif

- (void)stop
{
    if (_pressureSource) {
        dispatch_source_cancel(_pressureSource);
        _pressureSource = nil;
    }

    if (_limitSource) {
        dispatch_source_cancel(_limitSource);
        _limitSource = nil;
    }
}

/** Available system memory: truly free pages (excluding speculative, which the
 *  kernel read in opportunistically) plus the cached-files bucket (purgeable +
 *  file-backed pages) it can reclaim without compressing or swapping anonymous
 *  memory. Matches Activity Monitor's "Free + Cached Files".
 */
static uint64_t _AvailableSystemBytes(const vm_statistics64_data_t *stats)
{
    uint64_t speculative = (uint64_t)stats->speculative_count;
    uint64_t freeCount = (uint64_t)stats->free_count;
    uint64_t free = freeCount > speculative ? freeCount - speculative : 0;
    uint64_t cached = (uint64_t)stats->purgeable_count + (uint64_t)stats->external_page_count;
    return (free + cached) * (uint64_t)vm_kernel_page_size;
}

static KSCrashAppMemory *_Nullable _ProvideCrashAppMemory(KSCrashAppMemoryState pressure)
{
    task_vm_info_data_t info = {};
    mach_msg_type_number_t count = TASK_VM_INFO_COUNT;
    kern_return_t err = task_info(mach_task_self(), TASK_VM_INFO, (task_info_t)&info, &count);
    if (err != KERN_SUCCESS) {
        return nil;
    }

#if TARGET_OS_SIMULATOR
    // in simulator, remaining is always 0. So let's fake it.
    // How about a limit of 3GB.
    uint64_t limit = 3000000000;
    uint64_t remaining = limit < info.phys_footprint ? 0 : limit - info.phys_footprint;
#elif KSCRASH_HOST_MAC || TARGET_OS_MACCATALYST
    // macOS, Mac Catalyst included, doesn't limit memory usage the same way as other OSs
    // and reports no remaining bytes. So we just mock limit by having a large value instead (128 GB).
    uint64_t limit = 137438953472;  // 128 GB
    uint64_t remaining = limit < info.phys_footprint ? 0 : limit - info.phys_footprint;
#else
    uint64_t remaining = info.limit_bytes_remaining;
#endif

    // Fetched once: each mach_host_self() call adds a reference to the host
    // port's send right, so fetching it per sample would need a matching
    // mach_port_deallocate each time. Physical memory is process-lifetime
    // constant.
    static host_t hostPort;
    static uint64_t physicalMemory;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        hostPort = mach_host_self();
        physicalMemory = NSProcessInfo.processInfo.physicalMemory;
    });

    // Last successful system-wide sample. A transient host_statistics64
    // failure must not zero these: that would fabricate a headroom recovery
    // and wipe the sidecar's system values. Zero still means "never sampled".
    static _Atomic uint64_t lastSystemRemaining;
    static _Atomic uint64_t lastSystemLimit;

    vm_statistics64_data_t vmStats = {};
    mach_msg_type_number_t vmCount = HOST_VM_INFO64_COUNT;
    kern_return_t vmErr = host_statistics64(hostPort, HOST_VM_INFO64, (host_info64_t)&vmStats, &vmCount);
    uint64_t systemRemaining;
    uint64_t systemLimit;
    if (vmErr == KERN_SUCCESS) {
        systemRemaining = _AvailableSystemBytes(&vmStats);
        systemLimit = physicalMemory;
        atomic_store(&lastSystemRemaining, systemRemaining);
        atomic_store(&lastSystemLimit, systemLimit);
    } else {
        // Read the pair in the opposite order it is written: a nonzero limit
        // proves the matching remaining landed first.
        systemLimit = atomic_load(&lastSystemLimit);
        systemRemaining = systemLimit != 0 ? atomic_load(&lastSystemRemaining) : 0;
    }

    return [[KSCrashAppMemory alloc] initWithFootprint:info.phys_footprint
                                             remaining:remaining
                                              pressure:pressure
                                       systemRemaining:systemRemaining
                                           systemLimit:systemLimit];
}

- (nullable KSCrashAppMemory *)_appMemoryWithPressure:(KSCrashAppMemoryState)pressure
{
    KSCrashAppMemoryProvider provider = KSCrashAppMemoryGetProvider();
    return provider ? provider() : _ProvideCrashAppMemory(pressure);
}

- (nullable KSCrashAppMemory *)currentAppMemory
{
    return [self _appMemoryWithPressure:self.pressure];
}

/** Headroom, level, and pressure notifications are one family: async on the
 *  main queue with the same old/new userInfo shape. Change delivery here, not
 *  at the call sites. */
static void postStateChangeNotification(id object, NSNotificationName name, KSCrashAppMemoryState oldState,
                                        KSCrashAppMemoryState newState)
{
    dispatch_async(dispatch_get_main_queue(), ^{
        [[NSNotificationCenter defaultCenter] postNotificationName:name
                                                            object:object
                                                          userInfo:@{
                                                              KSCrashAppMemoryNewValueKey : @(newState),
                                                              KSCrashAppMemoryOldValueKey : @(oldState)
                                                          }];
    });
}

- (void)_handleMemoryChange:(KSCrashAppMemory *)memory
                       type:(KSCrashAppMemoryTrackerChangeType)changes
                  observers:(NSArray<KSCrashAppMemoryTrackerObserverBlock> *)observers
{
    if (memory == nil) {
        // Failed sample (task_info error): observers take a nonnull snapshot,
        // so drop the callback rather than hand them nil.
        return;
    }
    for (KSCrashAppMemoryTrackerObserverBlock obs in observers) {
        obs(memory, changes);
    }

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
    [self.delegate appMemoryTracker:self memory:memory changed:changes];
#pragma clang diagnostic pop
}

// in case of unsigned values
// ie: MAX(x,y) - MIN(x,y)
#define KSABS_DIFF(x, y) ((x) > (y) ? (x) - (y) : (y) - (x))

- (void)_heartbeat:(BOOL)sendObservers pressure:(KSCrashAppMemoryState)pressure
{
    // This handles the memory limit and system headroom.
    KSCrashAppMemory *memory = [self _appMemoryWithPressure:pressure];
    if (memory == nil) {
        // Failed sample (task_info error): skip the tick. Reading a nil
        // snapshot would see all zeros and fabricate level/headroom
        // recoveries while wiping the cached byte values.
        return;
    }

    KSCrashAppMemoryState newLevel = memory.level;
    KSCrashAppMemoryState newHeadroom = memory.headroom;
    KSCrashAppMemoryState newPressure = memory.pressure;
    uint64_t newFootprint = memory.footprint;
    uint64_t newSystemRemaining = memory.systemRemaining;

    NSArray<KSCrashAppMemoryTrackerObserverBlock> *observers = nil;
    KSCrashAppMemoryState oldLevel;
    KSCrashAppMemoryState oldHeadroom;
    KSCrashAppMemoryState oldPressure;
    KSCrashAppMemoryTrackerChangeType changes = KSCrashAppMemoryTrackerChangeTypeNone;
    {
        os_unfair_lock_lock(&_lock);

        oldLevel = _level;
        _level = newLevel;
        if (newLevel != oldLevel) {
            changes |= KSCrashAppMemoryTrackerChangeTypeLevel;
        }

        oldHeadroom = _headroom;
        _headroom = newHeadroom;
        if (newHeadroom != oldHeadroom) {
            changes |= KSCrashAppMemoryTrackerChangeTypeHeadroom;
        }

        // the amount footprint needs to change for any footprint notifs.
        const uint64_t kKSCrashFootprintMinChange = 1ULL << 20;  // 1 MiB

        // For the footprint, we don't need very granular changes,
        // changing a few bytes here or there won't mke a difference,
        // we're looking for anything larger.
        // A state transition always publishes the bytes that caused it, even
        // when the boundary was crossed by less than the threshold.
        if (newLevel != oldLevel || KSABS_DIFF(newFootprint, _footprint) > kKSCrashFootprintMinChange) {
            _footprint = newFootprint;
            changes |= KSCrashAppMemoryTrackerChangeTypeFootprint;
        }

        // Device-wide remaining is churned by every process on the system, so
        // its threshold scales with the device (1% of physical memory); the
        // 1 MiB footprint threshold would fire on nearly every heartbeat.
        const uint64_t kSystemRemainingMinChange = memory.systemLimit / 100;
        if (newHeadroom != oldHeadroom ||
            KSABS_DIFF(newSystemRemaining, _systemRemaining) > kSystemRemainingMinChange) {
            _systemRemaining = newSystemRemaining;
            changes |= KSCrashAppMemoryTrackerChangeTypeSystemRemaining;
        }

        oldPressure = _pressure;
        _pressure = newPressure;
        if (newPressure != oldPressure) {
            changes |= KSCrashAppMemoryTrackerChangeTypePressure;
        }

        // clear out NULLs from observers
        [_observers compact];
        observers = [_observers allObjects];
        os_unfair_lock_unlock(&_lock);
    }

    if (changes != KSCrashAppMemoryTrackerChangeTypeNone) {
        [self _handleMemoryChange:memory type:changes observers:observers];
    }

    if (newHeadroom != oldHeadroom && sendObservers) {
        postStateChangeNotification(self, KSCrashAppMemoryHeadroomChangedNotification, oldHeadroom, newHeadroom);
    }

    if (newPressure != oldPressure && sendObservers) {
        postStateChangeNotification(self, KSCrashAppMemoryPressureChangedNotification, oldPressure, newPressure);
    }

    if (newLevel != oldLevel && sendObservers) {
        postStateChangeNotification(self, KSCrashAppMemoryLevelChangedNotification, oldLevel, newLevel);
#if TARGET_OS_SIMULATOR

        // On the simulator, if we're at a terminal level
        // let's fake an OOM by sending a SIGKILL signal
        //
        // NOTE: Some teams might want to do this in prod.
        // For example, we could send a SIGTERM so the system
        // catches a stack trace.
        static BOOL sSimulatorMemoryKillEnabled;
        static dispatch_once_t onceToken;
        dispatch_once(&onceToken, ^{
            sSimulatorMemoryKillEnabled =
                [NSProcessInfo.processInfo.environment[@"KSCRASH_SIM_MEMORY_TERMINATION_ENABLED"] boolValue];
        });
        if (sSimulatorMemoryKillEnabled && newLevel == KSCrashAppMemoryStateTerminal) {
            kill(getpid(), SIGKILL);
            _exit(0);
        }
#endif
    }
}

- (KSCrashAppMemoryState)pressure
{
    KSCrashAppMemoryState state;
    {
        os_unfair_lock_lock(&_lock);
        state = _pressure;
        os_unfair_lock_unlock(&_lock);
    }
    return state;
}

- (KSCrashAppMemoryState)level
{
    KSCrashAppMemoryState state;
    {
        os_unfair_lock_lock(&_lock);
        state = _level;
        os_unfair_lock_unlock(&_lock);
    }
    return state;
}

- (KSCrashAppMemoryState)headroom
{
    KSCrashAppMemoryState state;
    {
        os_unfair_lock_lock(&_lock);
        state = _headroom;
        os_unfair_lock_unlock(&_lock);
    }
    return state;
}

@end
