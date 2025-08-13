#import "KSCrashAppMemoryTracker.h"

#import "KSCrashAppMemory+Private.h"
#import "KSSystemCapabilities.h"

#import <mach/mach.h>
#import <mach/task.h>
#import <os/lock.h>

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

@interface KSCrashAppMemoryTrackerBlockObserver : NSObject <KSCrashAppMemoryTrackerObserving>

@property(nonatomic, copy) KSCrashAppMemoryTrackerObserverBlock block;
@property(nonatomic, weak) id<KSCrashAppMemoryTrackerObserving> object;

@property(nonatomic, weak) KSCrashAppMemoryTracker *tracker;

- (BOOL)shouldReap;

@end

@implementation KSCrashAppMemoryTrackerBlockObserver

- (void)appMemoryTracker:(KSCrashAppMemoryTracker *)tracker
                  memory:(KSCrashAppMemory *)memory
                 changed:(KSCrashAppMemoryTrackerChangeType)changes
{
    KSCrashAppMemoryTrackerObserverBlock block = self.block;
    if (block) {
        block(memory, changes);
    }

    id<KSCrashAppMemoryTrackerObserving> object = self.object;
    if (object) {
        [object appMemoryTracker:self.tracker memory:memory changed:changes];
    }
}

- (BOOL)shouldReap
{
    return self.block == nil && self.object == nil;
}

@end

// I'm not protecting this.
// It should be set once at start if you want to change it for tests.
static KSCrashAppMemoryProvider gMemoryProvider = nil;
FOUNDATION_EXPORT void __KSCrashAppMemorySetProvider(KSCrashAppMemoryProvider provider)
{
    gMemoryProvider = [provider copy];
}

@interface KSCrashAppMemoryTracker () {
    dispatch_queue_t _heartbeatQueue;
    dispatch_source_t _pressureSource;
    dispatch_source_t _limitSource;

    os_unfair_lock _lock;
    uint64_t _footprint;
    KSCrashAppMemoryState _pressure;
    KSCrashAppMemoryState _level;
    NSMutableArray<id<KSCrashAppMemoryTrackerObserving>> *_observers;
}
@end

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
        _observers = [NSMutableArray array];
    }
    return self;
}

- (void)dealloc
{
    [self stop];
}

// Observers are either an object passed in that
// implements `KSCrashAppMemoryTrackerObserving` or a block.
// Both will be wrapped in a `KSCrashAppMemoryTrackerBlockObserver`.
// if a block, then it'll simply call the block.
// If the object, we'll keep a weak reference to it.
// Objects will be reaped when their block and their object
// is nil.
// We'll reap on add and removal or any type of observer.
- (void)_locked_reapObserversOrObject:(id)object
{
    NSMutableArray *toRemove = [NSMutableArray array];
    for (KSCrashAppMemoryTrackerBlockObserver *obj in _observers) {
        id<KSCrashAppMemoryTrackerObserving> strongObject = obj.object;
        if ((strongObject != nil && strongObject == object) || [obj shouldReap]) {
            [toRemove addObject:obj];
            obj.object = nil;
            obj.block = nil;
        }
    }
    [_observers removeObjectsInArray:toRemove];
}

- (void)_addObserver:(KSCrashAppMemoryTrackerBlockObserver *)observer
{
    os_unfair_lock_lock(&_lock);
    [_observers addObject:observer];
    [self _locked_reapObserversOrObject:nil];
    os_unfair_lock_unlock(&_lock);
}

- (void)addObserver:(id<KSCrashAppMemoryTrackerObserving>)observer
{
    KSCrashAppMemoryTrackerBlockObserver *obs = [[KSCrashAppMemoryTrackerBlockObserver alloc] init];
    obs.object = observer;
    obs.tracker = self;
    [self _addObserver:obs];
}

- (id<KSCrashAppMemoryTrackerObserving>)addObserverWithBlock:(KSCrashAppMemoryTrackerObserverBlock)block
{
    KSCrashAppMemoryTrackerBlockObserver *obs = [[KSCrashAppMemoryTrackerBlockObserver alloc] init];
    obs.block = [block copy];
    obs.tracker = self;
    [self _addObserver:obs];
    return obs;
}

- (void)removeObserver:(id<KSCrashAppMemoryTrackerObserving>)observer
{
    os_unfair_lock_lock(&_lock);

    // Observers added with a block
    if ([observer isKindOfClass:KSCrashAppMemoryTrackerBlockObserver.class]) {
        KSCrashAppMemoryTrackerBlockObserver *obs = (KSCrashAppMemoryTrackerBlockObserver *)observer;
        obs.block = nil;
        obs.object = nil;
        [self _locked_reapObserversOrObject:nil];
    }

    // observers added with an object
    else {
        [self _locked_reapObserversOrObject:observer];
    }

    os_unfair_lock_unlock(&_lock);
}

- (void)start
{
    // kill the old ones
    if (_pressureSource || _limitSource) {
        [self stop];
    }

    // memory pressure
    uintptr_t mask = DISPATCH_MEMORYPRESSURE_NORMAL | DISPATCH_MEMORYPRESSURE_WARN | DISPATCH_MEMORYPRESSURE_CRITICAL;
    _pressureSource = dispatch_source_create(DISPATCH_SOURCE_TYPE_MEMORYPRESSURE, 0, mask, dispatch_get_main_queue());

    __weak __typeof(self) weakMe = self;

    dispatch_source_set_event_handler(_pressureSource, ^{
        [weakMe _memoryPressureChanged:YES];
    });
    dispatch_activate(_pressureSource);

    // memory limit (level)
    _limitSource = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, _heartbeatQueue);
    dispatch_source_set_event_handler(_limitSource, ^{
        [weakMe _heartbeat:YES];
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
    [self _handleMemoryChange:[self currentAppMemory]
                         type:KSCrashAppMemoryTrackerChangeTypeNone
                    observers:[_observers copy]];
}

#if KSCRASH_HAS_UIAPPLICATION
- (void)_appDidFinishLaunching
{
    [self _handleMemoryChange:[self currentAppMemory]
                         type:KSCrashAppMemoryTrackerChangeTypeNone
                    observers:[_observers copy]];
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
    // How about a limit of 6GB.
    uint64_t limit = 6000000000;
    uint64_t remaining = limit < info.phys_footprint ? 0 : limit - info.phys_footprint;
#elif KSCRASH_HOST_MAC
    // macOS doesn't limit memory usage the same way as it's implemented for other OSs.
    // So we just mock limit by having a large value instead (128 GB).
    uint64_t limit = 137438953472;  // 128 GB
    uint64_t remaining = limit < info.phys_footprint ? 0 : limit - info.phys_footprint;
#else
    uint64_t remaining = info.limit_bytes_remaining;
#endif

    return [[KSCrashAppMemory alloc] initWithFootprint:info.phys_footprint remaining:remaining pressure:pressure];
}

- (nullable KSCrashAppMemory *)currentAppMemory
{
    return gMemoryProvider ? gMemoryProvider() : _ProvideCrashAppMemory(_pressure);
}

- (void)_handleMemoryChange:(KSCrashAppMemory *)memory
                       type:(KSCrashAppMemoryTrackerChangeType)changes
                  observers:(NSArray<id<KSCrashAppMemoryTrackerObserving>> *)observers
{
    for (id<KSCrashAppMemoryTrackerObserving> obs in observers) {
        [obs appMemoryTracker:self memory:memory changed:changes];
    }

    [self.delegate appMemoryTracker:self memory:memory changed:changes];
}

// in case of unsigned values
// ie: MAX(x,y) - MIN(x,y)
#define _KSABS_DIFF(x, y) x > y ? x - y : y - x

- (void)_heartbeat:(BOOL)sendObservers
{
    // This handles the memory limit.
    KSCrashAppMemory *memory = [self currentAppMemory];

    KSCrashAppMemoryState newLevel = memory.level;
    uint64_t newFootprint = memory.footprint;

    NSArray<id<KSCrashAppMemoryTrackerObserving>> *observers = nil;
    KSCrashAppMemoryState oldLevel;
    BOOL footprintChanged = NO;
    {
        os_unfair_lock_lock(&_lock);

        oldLevel = _level;
        _level = newLevel;

        // the amount footprint needs to change for any footprint notifs.
        const uint64_t kKSCrashFootprintMinChange = 1 << 20;  // 1 MiB

        // For the footprint, we don't need very granular changes,
        // changing a few bytes here or there won't mke a difference,
        // we're looking for anything larger.
        if (_KSABS_DIFF(newFootprint, _footprint) > kKSCrashFootprintMinChange) {
            _footprint = newFootprint;
            footprintChanged = YES;
        }

        observers = [_observers copy];
        os_unfair_lock_unlock(&_lock);
    }

    KSCrashAppMemoryTrackerChangeType changes =
        (newLevel != oldLevel) ? KSCrashAppMemoryTrackerChangeTypeLevel : KSCrashAppMemoryTrackerChangeTypeNone;

    if (footprintChanged) {
        changes |= KSCrashAppMemoryTrackerChangeTypeFootprint;
    }

    if (changes != KSCrashAppMemoryTrackerChangeTypeNone) {
        [self _handleMemoryChange:memory type:changes observers:observers];
    }

    if (newLevel != oldLevel && sendObservers) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [[NSNotificationCenter defaultCenter] postNotificationName:KSCrashAppMemoryLevelChangedNotification
                                                                object:self
                                                              userInfo:@{
                                                                  KSCrashAppMemoryNewValueKey : @(newLevel),
                                                                  KSCrashAppMemoryOldValueKey : @(oldLevel)
                                                              }];
        });
#if TARGET_OS_SIMULATOR

        // On the simulator, if we're at a terminal level
        // let's fake an OOM by sending a SIGKILL signal
        //
        // NOTE: Some teams might want to do this in prod.
        // For example, we could send a SIGTERM so the system
        // catches a stack trace.
        static BOOL sIsRunningInTests;
        static BOOL sSimulatorMemoryKillEnabled;
        static dispatch_once_t onceToken;
        dispatch_once(&onceToken, ^{
            NSDictionary<NSString *, NSString *> *env = NSProcessInfo.processInfo.environment;
            sIsRunningInTests = env[@"XCTestSessionIdentifier"] != nil;
            sSimulatorMemoryKillEnabled = [env[@"KSCRASH_SIM_MEMORY_TERMINATION_ENABLED"] boolValue];
        });
        if (sSimulatorMemoryKillEnabled && !sIsRunningInTests && newLevel == KSCrashAppMemoryStateTerminal) {
            kill(getpid(), SIGKILL);
            _exit(0);
        }
#endif
    }
}

- (void)_memoryPressureChanged:(BOOL)sendObservers
{
    // This handles system based memory pressure.
    KSCrashAppMemoryState newPressure = KSCrashAppMemoryStateNormal;
    dispatch_source_memorypressure_flags_t flags = dispatch_source_get_data(_pressureSource);
    switch (flags) {
        case DISPATCH_MEMORYPRESSURE_NORMAL:
            newPressure = KSCrashAppMemoryStateNormal;
            break;
        case DISPATCH_MEMORYPRESSURE_WARN:
            newPressure = KSCrashAppMemoryStateWarn;
            break;
        case DISPATCH_MEMORYPRESSURE_CRITICAL:
            newPressure = KSCrashAppMemoryStateCritical;
            break;
        default:
            newPressure = KSCrashAppMemoryStateNormal;
    }

    NSArray<id<KSCrashAppMemoryTrackerObserving>> *observers = nil;
    KSCrashAppMemoryState oldPressure;
    {
        os_unfair_lock_lock(&_lock);
        oldPressure = _pressure;
        _pressure = newPressure;
        observers = [_observers copy];
        os_unfair_lock_unlock(&_lock);
    }

    if (oldPressure != newPressure && sendObservers) {
        [self _handleMemoryChange:[self currentAppMemory]
                             type:KSCrashAppMemoryTrackerChangeTypePressure
                        observers:observers];
        [[NSNotificationCenter defaultCenter] postNotificationName:KSCrashAppMemoryPressureChangedNotification
                                                            object:self
                                                          userInfo:@{
                                                              KSCrashAppMemoryNewValueKey : @(newPressure),
                                                              KSCrashAppMemoryOldValueKey : @(oldPressure)
                                                          }];
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

@end
