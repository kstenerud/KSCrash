#import "KSCrashAppMemory.h"

#import <mach/mach.h>
#import <mach/task.h>
#import <atomic>

#if TARGET_OS_IOS
#import <UIKit/UIKit.h>
#endif

NS_ASSUME_NONNULL_BEGIN

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
 `footprint`. Using this data, we can also make informaed decisions around foreground and background
 memory terminations, aka. OOMs.
 
 See: https://github.com/naftaly/Footprint
 */

@interface KSCrashAppMemoryTracker () {
    dispatch_queue_t _heartbeatQueue;
    dispatch_source_t _pressureSource;
    dispatch_source_t _limitSource;
    std::atomic<uint64_t> _footprint;
    std::atomic<KSCrashAppMemoryState> _pressure;
    std::atomic<KSCrashAppMemoryState> _level;
}
@end

@implementation KSCrashAppMemoryTracker

- (instancetype)init {
    if (self = [super init]) {
        _heartbeatQueue = dispatch_queue_create_with_target(
                                                            "com.kscrash.memory.heartbeat", DISPATCH_QUEUE_SERIAL,
                                                            dispatch_get_global_queue(QOS_CLASS_UTILITY, 0));
        _level = KSCrashAppMemoryStateNormal;
        _pressure = KSCrashAppMemoryStateNormal;
    }
    return self;
}

- (void)dealloc {
    [self stop];
}

- (void)start {
    // kill the old ones
    if (_pressureSource || _limitSource) {
        [self stop];
    }
    
    // memory pressure
    uintptr_t mask = DISPATCH_MEMORYPRESSURE_NORMAL | DISPATCH_MEMORYPRESSURE_WARN |
    DISPATCH_MEMORYPRESSURE_CRITICAL;
    _pressureSource = dispatch_source_create(DISPATCH_SOURCE_TYPE_MEMORYPRESSURE, 0, mask,
                                             dispatch_get_main_queue());
    
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
    dispatch_source_set_timer(_limitSource, dispatch_time(DISPATCH_TIME_NOW, 0), NSEC_PER_SEC,
                              NSEC_PER_SEC / 10);
    dispatch_activate(_limitSource);
    
#if TARGET_OS_IOS
    // We won't always hit this depending on how the system is setup in the app,
    // but at least we can try.
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(_appDidFinishLaunching)
                                                 name:UIApplicationDidFinishLaunchingNotification
                                               object:nil];
#endif
    [self _handleMemoryChange:[self currentAppMemory] type:KSCrashAppMemoryTrackerChangeTypeNone];
}

#if TARGET_OS_IOS
- (void)_appDidFinishLaunching {
    [self _handleMemoryChange:[self currentAppMemory] type:KSCrashAppMemoryTrackerChangeTypeNone];
}
#endif

- (void)stop {
    if (_pressureSource) {
        dispatch_source_cancel(_pressureSource);
        _pressureSource = nil;
    }
    
    if (_limitSource) {
        dispatch_source_cancel(_limitSource);
        _limitSource = nil;
    }
}

- (nullable KSCrashAppMemory *)currentAppMemory {
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
#else
    uint64_t remaining = info.limit_bytes_remaining;
#endif
    
    return [[KSCrashAppMemory alloc] initWithFootprint:info.phys_footprint
                                             remaining:remaining
                                              pressure:_pressure];
}

- (void)_handleMemoryChange:(KSCrashAppMemory *)memory type:(KSCrashAppMemoryTrackerChangeType)changes {
    [self.delegate appMemoryTracker:self memory:memory changed:changes];
}

- (void)_heartbeat:(BOOL)sendObservers {

    // This handles the memory limit.
    KSCrashAppMemory *memory = [self currentAppMemory];
    
    KSCrashAppMemoryState newLevel = memory.level;
    KSCrashAppMemoryState oldLevel = _level.exchange(newLevel);
    
    uint64_t newFootprint = memory.footprint;
    uint64_t oldFootprint = _footprint.exchange(newFootprint);
    
    KSCrashAppMemoryTrackerChangeType changes = (newLevel != oldLevel) ? KSCrashAppMemoryTrackerChangeTypeLevel : KSCrashAppMemoryTrackerChangeTypeNone;
    // if the footprint has changed by at least 1MB
    if ( ABS(newFootprint - oldFootprint) > 1e6) {
        changes |= KSCrashAppMemoryTrackerChangeTypeFootprint;
    }
    
    if (changes != KSCrashAppMemoryTrackerChangeTypeNone) {
        [self _handleMemoryChange:memory type:changes];
    }
    
    if (newLevel != oldLevel && sendObservers) {
        
        dispatch_async(dispatch_get_main_queue(), ^{
            [[NSNotificationCenter defaultCenter]
             postNotificationName:KSCrashAppMemoryLevelChangedNotification
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
        if (newLevel == KSCrashAppMemoryStateTerminal) {
            kill(getpid(), SIGKILL);
            _exit(0);
        }
#endif
    }
}

- (void)_memoryPressureChanged:(BOOL)sendObservers {
    // This handles system based memory pressure.
    KSCrashAppMemoryState pressure = KSCrashAppMemoryStateNormal;
    dispatch_source_memorypressure_flags_t flags = dispatch_source_get_data(_pressureSource);
    if (flags == DISPATCH_MEMORYPRESSURE_NORMAL) {
        pressure = KSCrashAppMemoryStateNormal;
    } else if (flags == DISPATCH_MEMORYPRESSURE_WARN) {
        pressure = KSCrashAppMemoryStateWarn;
    } else if (flags == DISPATCH_MEMORYPRESSURE_CRITICAL) {
        pressure = KSCrashAppMemoryStateCritical;
    }
    KSCrashAppMemoryState oldPressure = _pressure.exchange(pressure);
    if (oldPressure != pressure && sendObservers) {
        [self _handleMemoryChange:[self currentAppMemory]
                             type:KSCrashAppMemoryTrackerChangeTypePressure];
        [[NSNotificationCenter defaultCenter]
         postNotificationName:KSCrashAppMemoryPressureChangedNotification
         object:self
         userInfo:@{
            KSCrashAppMemoryNewValueKey : @(pressure),
            KSCrashAppMemoryOldValueKey : @(oldPressure)
        }];
    }
}

- (KSCrashAppMemoryState)pressure {
    return _pressure.load();
}

- (KSCrashAppMemoryState)level {
    return _level.load();
}

@end

@implementation KSCrashAppMemory

- (instancetype)initWithFootprint:(uint64_t)footprint
                        remaining:(uint64_t)remaining
                         pressure:(KSCrashAppMemoryState)pressure {
    if (self = [super init]) {
        _footprint = footprint;
        _remaining = remaining;
        _pressure = pressure;
    }
    return self;
}

- (nullable instancetype)initWithJSONObject:(NSDictionary *)jsonObject {
    NSNumber *const footprintRef = jsonObject[@"memory_footprint"];
    NSNumber *const remainingRef = jsonObject[@"memory_remaining"];
    NSString *const pressureRef = jsonObject[@"memory_pressure"];
    
    uint64_t footprint = 0;
    if ([footprintRef isKindOfClass:NSNumber.class]) {
        footprint = footprintRef.unsignedLongLongValue;
    } else if ([footprintRef isKindOfClass:NSString.class]) {
        footprint = ((NSString *)footprintRef).longLongValue;
    } else {
        return nil;
    }
    
    uint64_t remaining = 0;
    if ([remainingRef isKindOfClass:NSNumber.class]) {
        remaining = remainingRef.unsignedLongLongValue;
    } else if ([remainingRef isKindOfClass:NSString.class]) {
        remaining = ((NSString *)remainingRef).longLongValue;
    } else {
        return nil;
    }
    
    KSCrashAppMemoryState pressure = KSCrashAppMemoryStateNormal;
    if ([pressureRef isKindOfClass:NSString.class]) {
        pressure = KSCrashAppMemoryStateFromString(pressureRef);
    }
    
    return [self initWithFootprint:footprint remaining:remaining pressure:pressure];
}

- (BOOL)isEqual:(id)object {
    if (![object isKindOfClass:self.class]) {
        return NO;
    }
    KSCrashAppMemory *comp = (KSCrashAppMemory *)object;
    return comp.footprint == self.footprint && comp.remaining == self.remaining &&
    comp.pressure == self.pressure;
}

- (nonnull NSDictionary<NSString *, id> *)serialize {
    return @{
        @"memory_footprint" : @(self.footprint),
        @"memory_remaining" : @(self.remaining),
        @"memory_limit" : @(self.limit),
        @"memory_level" : KSCrashAppMemoryStateToString(self.level),
        @"memory_pressure" : KSCrashAppMemoryStateToString(self.pressure)
    };
}

- (uint64_t)limit {
    return _footprint + _remaining;
}

- (KSCrashAppMemoryState)level {
    double usedRatio = (double)self.footprint / (double)self.limit;
    
    return usedRatio < 0.25   ? KSCrashAppMemoryStateNormal
    : usedRatio < 0.50 ? KSCrashAppMemoryStateWarn
    : usedRatio < 0.75 ? KSCrashAppMemoryStateUrgent
    : usedRatio < 0.95 ? KSCrashAppMemoryStateCritical
    : KSCrashAppMemoryStateTerminal;
}

- (BOOL)isOutOfMemory {
    return self.level >= KSCrashAppMemoryStateCritical ||
    self.pressure >= KSCrashAppMemoryStateCritical;
}

@end

NSString *KSCrashAppMemoryStateToString(KSCrashAppMemoryState state) {
    switch (state) {
        case KSCrashAppMemoryStateNormal:
            return @"normal";
        case KSCrashAppMemoryStateWarn:
            return @"warn";
        case KSCrashAppMemoryStateUrgent:
            return @"urgent";
        case KSCrashAppMemoryStateCritical:
            return @"critical";
        case KSCrashAppMemoryStateTerminal:
            return @"terminal";
    }
}

KSCrashAppMemoryState KSCrashAppMemoryStateFromString(NSString *const state) {
    if ([state isEqualToString:@"normal"]) {
        return KSCrashAppMemoryStateNormal;
    }
    
    if ([state isEqualToString:@"warn"]) {
        return KSCrashAppMemoryStateWarn;
    }
    
    if ([state isEqualToString:@"urgent"]) {
        return KSCrashAppMemoryStateUrgent;
    }
    
    if ([state isEqualToString:@"critical"]) {
        return KSCrashAppMemoryStateCritical;
    }
    
    if ([state isEqualToString:@"terminal"]) {
        return KSCrashAppMemoryStateTerminal;
    }
    
    return KSCrashAppMemoryStateNormal;
}

NSNotificationName const KSCrashAppMemoryLevelChangedNotification =
@"KSCrashAppMemoryLevelChangedNotification";
NSNotificationName const KSCrashAppMemoryPressureChangedNotification =
@"KSCrashAppMemoryPressureChangedNotification";
NSString *const KSCrashAppMemoryNewValueKey = @"KSCrashAppMemoryNewValueKey";
NSString *const KSCrashAppMemoryOldValueKey = @"KSCrashAppMemoryOldValueKey";

NS_ASSUME_NONNULL_END