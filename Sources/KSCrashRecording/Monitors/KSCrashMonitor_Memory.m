//
//  KSCrashMonitor_NSException.m
//
//  Created by Karl Stenerud on 2012-01-28.
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
#import "KSCrashMonitor_Memory.h"

#import "KSCrash.h"
#import "KSCrashC.h"
#import "KSCrashMonitorContext.h"
#import "KSCrashAppMemory.h"
#import "KSID.h"
#import "KSStackCursor.h"
#import "KSStackCursor_SelfThread.h"
#import "KSStackCursor_MachineContext.h"
#import "KSCrashReportFields.h"
#import "KSDate.h"
#import "KSFileUtils.h"

#import <Foundation/Foundation.h>
#import <os/lock.h>

#import "KSLogger.h"

#if TARGET_OS_IOS
#import <UIKit/UIKit.h>
#endif

// ============================================================================
#pragma mark - Forward declarations -
// ============================================================================

static KSCrash_Memory _ks_memory_copy(void);
static void _ks_memory_update(void (^block)(KSCrash_Memory *mem));
static void ksmemory_write_possible_oom(void);
static void setEnabled(bool isEnabled);
static bool isEnabled(void);
static NSString *kscm_app_transition_state_to_string(KSCrash_ApplicationTransitionState state);
static NSURL *kscm_memory_oom_breadcrumb_URL(void);
static void addContextualInfoToEvent(KSCrash_MonitorContext* eventContext);
static NSDictionary<NSString *, id> *kscm_memory_serialize(KSCrash_Memory *const memory);
static void kscm_memory_check_for_oom_in_previous_session(void);
static void notifyPostSystemEnable(void);
static void ksmemory_read(const char* path);
static void ksmemory_map(const char* path);

// ============================================================================
#pragma mark - Globals -
// ============================================================================

static volatile bool g_isEnabled = 0;
static volatile bool g_hasPostEnable = 0;

// Install path for the crash system
static NSURL *g_installURL = nil;

// The memory tracker
@class MemoryTracker;
static MemoryTracker *g_memoryTracker = nil;

// file mapped memory.
// Never touch `g_memory` directly,
// always call `_ks_memory_update`.
// ex:
// _ks_memory_update(^(KSCrash_Memory *mem){
//      mem->x = ...
//  });
static os_unfair_lock g_memoryLock = OS_UNFAIR_LOCK_INIT;
static KSCrash_Memory *g_memory = NULL;

static KSCrash_Memory _ks_memory_copy(void) {
    KSCrash_Memory copy = {0};
    {
        os_unfair_lock_lock(&g_memoryLock);
        if (g_memory) {
            copy = *g_memory;
        }
        os_unfair_lock_unlock(&g_memoryLock);
    }
    return copy;
}

static void _ks_memory_update(void (^block)(KSCrash_Memory *mem)) {
    if (!block) {
        return;
    }
    os_unfair_lock_lock(&g_memoryLock);
    if (g_memory) {
        block(g_memory);
    }
    os_unfair_lock_unlock(&g_memoryLock);
}

// last memory write from the previous session
static KSCrash_Memory g_previousSessionMemory;

// App state tracking
@class AppStateTracker;
static AppStateTracker *g_AppStateTracker = nil;

// ============================================================================
#pragma mark - App State Tracking -
// ============================================================================

/**
 AppStateTracker
 
 This system tracks the app state, but also gives insight into the transitions
 from launch to termination. One reason why this is useful is that when a user
 brings a running process to the foreground, it goes through an animation from
 background to foreground that is not accounted for in UIApplicationState but
 is still visible to users. If the app crashes or is temrinated during that time, the
 application state is `UIApplicationStateBackground` which is usually not
 accounted for in crash systems. This newer method with transitions included in
 the state is much more complete and allows products to be much more reliable
 and handle areas of the app that are very important to users but rarely handled
 by apps.
 
 We'll keep it private for now until it is integrated with `KSCrashMonitor_AppState`.
 */
@protocol AppStateTrackerObserving <NSObject>
- (void)appStateTrackerDidChangeApplicationTransitionState:(KSCrash_ApplicationTransitionState)transitionState;
@end

typedef void (^AppStateTrackerBlockObserverBlock)(KSCrash_ApplicationTransitionState transitionState);
@interface AppStateTrackerBlockObserver : NSObject <AppStateTrackerObserving>

@property (nonatomic, copy) AppStateTrackerBlockObserverBlock block;
@property (nonatomic, weak) id<AppStateTrackerObserving> object;

- (BOOL)shouldReap;

@end

@implementation AppStateTrackerBlockObserver

- (void)appStateTrackerDidChangeApplicationTransitionState:(KSCrash_ApplicationTransitionState)transitionState
{
    AppStateTrackerBlockObserverBlock block = self.block;
    if (block) {
        block(transitionState);
    }
    
    id<AppStateTrackerObserving> object = self.object;
    if (object) {
        [object appStateTrackerDidChangeApplicationTransitionState:transitionState];
    }
}

- (BOOL)shouldReap
{
    return self.block == nil && self.object == nil;
}

@end

@interface AppStateTracker : NSObject {
    
    NSNotificationCenter *_center;
    NSArray<id<NSObject>> *_registrations;
    
    // transition state and observers protected by the lock
    os_unfair_lock _lock;
    KSCrash_ApplicationTransitionState _transitionState;
    NSMutableArray<id<AppStateTrackerObserving>> *_observers;
}

- (instancetype)initWithNotificationCenter:(NSNotificationCenter *)notificationCenter NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;
+ (instancetype)new NS_UNAVAILABLE;

@property (atomic, readonly) KSCrash_ApplicationTransitionState transitionState;

- (void)addObserver:(id<AppStateTrackerObserving>)observer;
- (id<AppStateTrackerObserving>)addObserverWithBlock:(AppStateTrackerBlockObserverBlock)block;

- (void)removeObserver:(id<AppStateTrackerObserving>)observer;

@end

@implementation AppStateTracker

static id<AppStateTrackerObserving> S_OBS = nil;

+ (void)load
{
    g_AppStateTracker = [[AppStateTracker alloc] initWithNotificationCenter:NSNotificationCenter.defaultCenter];
    S_OBS = [g_AppStateTracker addObserverWithBlock:^(KSCrash_ApplicationTransitionState transitionState) {
        _ks_memory_update(^(KSCrash_Memory *mem) {
            mem->state = transitionState;
        });
    }];
    [g_AppStateTracker start];
}

- (instancetype)initWithNotificationCenter:(NSNotificationCenter *)notificationCenter
{
    if (self = [super init]) {
        _lock = OS_UNFAIR_LOCK_INIT;
        _observers = [NSMutableArray array];
        _center = notificationCenter;
        _registrations = nil;
        
        BOOL isPrewarm = [NSProcessInfo.processInfo.environment[@"ActivePrewarm"] boolValue];
        _transitionState = isPrewarm ? KSCrash_ApplicationTransitionStateStartup : KSCrash_ApplicationTransitionStateStartup;
    }
    return self;
}

- (void)dealloc
{
    [self stop];
}

// Observers are either an object passed in that
// implements `AppStateTrackerObserving` or a block.
// Both will be wrapped in a `AppStateTrackerBlockObserver`.
// if a block, then it'll simply call the block.
// If the object, we'll keep a weak reference to it.
// Objects will be reaped when their block and their object
// is nil.
// We'll reap on add and removal or any type of observer.
- (void)_locked_reapObserversOrObject:(id)object
{
    NSMutableArray *toRemove = [NSMutableArray array];
    for (AppStateTrackerBlockObserver *obj in _observers) {
        if ((obj.object != nil && obj.object == object) || [obj shouldReap]) {
            [toRemove addObject:obj];
            obj.object = nil;
            obj.block = nil;
        }
    }
    [_observers removeObjectsInArray:toRemove];
}

- (void)_addObserver:(AppStateTrackerBlockObserver *)observer
{
    os_unfair_lock_lock(&_lock);
    [_observers addObject:observer];
    [self _locked_reapObserversOrObject:nil];
    os_unfair_lock_unlock(&_lock);
}

- (void)addObserver:(id<AppStateTrackerObserving>)observer
{
    AppStateTrackerBlockObserver *obs = [[AppStateTrackerBlockObserver alloc] init];
    obs.object = observer;
    [self _addObserver:obs];
}

- (id<AppStateTrackerObserving>)addObserverWithBlock:(AppStateTrackerBlockObserverBlock)block
{
    AppStateTrackerBlockObserver *obs = [[AppStateTrackerBlockObserver alloc] init];
    obs.block = [block copy];
    [self _addObserver:obs];
    return obs;
}

- (void)removeObserver:(id<AppStateTrackerObserving>)observer
{
    os_unfair_lock_lock(&_lock);
    
    // Observers added with a block
    if ([observer isKindOfClass:AppStateTrackerBlockObserver.class]) {
        AppStateTrackerBlockObserver *obs = (AppStateTrackerBlockObserver *)observer;
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

- (KSCrash_ApplicationTransitionState)transitionState
{
    KSCrash_ApplicationTransitionState ret;
    {
        os_unfair_lock_lock(&_lock);
        ret = _transitionState;
        os_unfair_lock_unlock(&_lock);
    }
    return ret;
}

- (void)_setTransitionState:(KSCrash_ApplicationTransitionState)transitionState
{
    NSArray<id<AppStateTrackerObserving>> *observers = nil;
    {
        os_unfair_lock_lock(&_lock);
        if (_transitionState != transitionState) {
            _transitionState = transitionState;
            observers = [_observers copy];
        }
        os_unfair_lock_unlock(&_lock);
    }
    
    for (id<AppStateTrackerObserving> obs in observers) {
        [obs appStateTrackerDidChangeApplicationTransitionState:transitionState];
    }
}

#define OBSERVE(center, name, block) \
    [center addObserverForName:name \
    object:nil \
    queue:nil \
    usingBlock:^(NSNotification *notification)block] \

- (void)start
{
    if (_registrations) {
        return;
    }
    
    __weak typeof(self)weakMe = self;
    
    // Register a normal `exit` callback so we don't think it's an OOM.
    atexit_b(^{
        [weakMe _setTransitionState:KSCrash_ApplicationTransitionStateExiting];
    });
    
    // TODO: What other supported platforms need something like this???
#if TARGET_OS_IOS

    // register all normal lifecycle events
    // in the future, we could also look at scene lifecycle
    // events but in reality, we don't actually need to,
    // it could just give us more granularity.
    _registrations = @[
        
        OBSERVE(_center, UIApplicationDidFinishLaunchingNotification, {
            [weakMe _setTransitionState:KSCrash_ApplicationTransitionStateLaunching];
        }),
        OBSERVE(_center, UIApplicationWillEnterForegroundNotification, {
            [weakMe _setTransitionState:KSCrash_ApplicationTransitionStateForegrounding];
        }),
        OBSERVE(_center, UIApplicationDidBecomeActiveNotification, {
            [weakMe _setTransitionState:KSCrash_ApplicationTransitionStateActive];
        }),
        OBSERVE(_center, UIApplicationWillResignActiveNotification, {
            [weakMe _setTransitionState:KSCrash_ApplicationTransitionStateDeactivating];
        }),
        OBSERVE(_center, UIApplicationDidEnterBackgroundNotification, {
            [weakMe _setTransitionState:KSCrash_ApplicationTransitionStateBackground];
        }),
        OBSERVE(_center, UIApplicationWillTerminateNotification, {
            [weakMe _setTransitionState:KSCrash_ApplicationTransitionStateTerminating];
        }),
    ];
#endif
}

- (void)stop
{
    NSArray<id<NSObject>> *registraions = [_registrations copy];
    _registrations = nil;
    for (id<NSObject> registraion in registraions) {
        [_center removeObserver:registraion];
    }
}

@end

// ============================================================================
#pragma mark - Tracking -
// ============================================================================

@interface MemoryTracker : NSObject <KSCrashAppMemoryTrackerDelegate> {
    KSCrashAppMemoryTracker *_tracker;
}
@end

@implementation MemoryTracker

- (instancetype)init
{
    if (self = [super init]) {
        _tracker = [[KSCrashAppMemoryTracker alloc] init];
        _tracker.delegate = self;
        [_tracker start];
    }
    return self;
}

- (void)dealloc
{
    [_tracker stop];
}

- (KSCrashAppMemory *)memory
{
    return _tracker.currentAppMemory;
}

- (void)_updateMappedMemoryFrom:(KSCrashAppMemory *)memory
{
    _ks_memory_update(^(KSCrash_Memory *mem) {
        *mem = (KSCrash_Memory){
            .footprint = memory.footprint,
            .remaining = memory.remaining,
            .limit = memory.limit,
            .pressure = (uint8_t)memory.pressure,
            .level = (uint8_t)memory.level,
            .timestamp = ksdate_microseconds(),
            .state = g_AppStateTracker.transitionState,
        };
    });
}

- (void)appMemoryTracker:(KSCrashAppMemoryTracker *)tracker memory:(KSCrashAppMemory *)memory changed:(KSCrashAppMemoryTrackerChangeType)changes
{
    if (changes & KSCrashAppMemoryTrackerChangeTypeFootprint) {
        [self _updateMappedMemoryFrom:memory];
    }
    
    if ((changes & KSCrashAppMemoryTrackerChangeTypeLevel) &&
        memory.level >= KSCrashAppMemoryStateCritical) {

        NSString *level = KSCrashAppMemoryStateToString(memory.level).uppercaseString;
        NSString *reason = [NSString stringWithFormat:@"Memory Level Is %@", level];
        
        [[KSCrash sharedInstance] reportUserException:@"Memory Level"
                                               reason:reason
                                             language:@""
                                           lineOfCode:@"0"
                                           stackTrace:@[@"__MEMORY_LEVEL_HIGH___OOM_IS_IMMINENT__"]
                                        logAllThreads:NO
                                     terminateProgram:NO];
    }
    
    if ((changes & KSCrashAppMemoryTrackerChangeTypePressure) &&
        memory.pressure >= KSCrashAppMemoryStateCritical) {

        NSString *pressure = KSCrashAppMemoryStateToString(memory.pressure).uppercaseString;
        NSString *reason = [NSString stringWithFormat:@"Memory Pressure Is %@", pressure];
        
        [[KSCrash sharedInstance] reportUserException:@"Memory Pressure "
                                               reason:reason
                                             language:@""
                                           lineOfCode:@"0"
                                           stackTrace:@[@"__MEMORY_PRESSURE_HIGH___OOM_IS_IMMINENT__"]
                                        logAllThreads:NO
                                     terminateProgram:NO];
    }
}

@end

// ============================================================================
#pragma mark - API -
// ============================================================================

static void setEnabled(bool isEnabled)
{
    if (isEnabled != g_isEnabled)
    {
        g_isEnabled = isEnabled;
        if(isEnabled)
        {
            if (g_hasPostEnable) {
                g_memoryTracker = [[MemoryTracker alloc] init];
            }
        }
        else
        {
            g_memoryTracker = nil;
        }
    }
}

static bool isEnabled(void)
{
    return g_isEnabled;
}

static NSString *kscm_app_transition_state_to_string(KSCrash_ApplicationTransitionState state) {
    switch (state) {
        case KSCrash_ApplicationTransitionStateStartup: return @"startup";
        case KSCrash_ApplicationTransitionStateStartupPrewarm: return @"prewarm";
        case KSCrash_ApplicationTransitionStateActive: return @"active";
        case KSCrash_ApplicationTransitionStateLaunching: return @"launching";
        case KSCrash_ApplicationTransitionStateBackground: return @"background";
        case KSCrash_ApplicationTransitionStateTerminating: return @"terminating";
        case KSCrash_ApplicationTransitionStateExiting: return @"exiting";
        case KSCrash_ApplicationTransitionStateDeactivating: return @"deactivating";
        case KSCrash_ApplicationTransitionStateForegrounding: return @"foregrounding";
    }
    return @"unknown";
}

static NSURL *kscm_memory_oom_breadcrumb_URL(void) {
    return [g_installURL URLByAppendingPathComponent:@"Data/oom_breadcrumb_report.json"];
}

static void addContextualInfoToEvent(KSCrash_MonitorContext* eventContext)
{
    // TODO: Make this fully async safe
    
    // we'll use this when reading this back on the next run
    // to know if an OOM is even possible.
    _ks_memory_update(^(KSCrash_Memory *mem) {
        mem->fatal = eventContext->handlingCrash ? 1 : 0;
    });
    
    if (g_isEnabled)
    {
        // Not sure if I can lock here or not, we might be in an async only state.
        // Chances are we don't really need to anyway.
        // In any case, make a copy of the data so we don't keep the lock for long.
        KSCrash_Memory memCopy = _ks_memory_copy();

        // Not async safe.
        eventContext->AppMemory.footprint = memCopy.footprint;
        // `.UTF8String` here is ok because the implementation uses constants,
        // so they're built into the app and will always exist.
        eventContext->AppMemory.pressure = KSCrashAppMemoryStateToString((KSCrashAppMemoryState)memCopy.pressure).UTF8String;
        eventContext->AppMemory.remaining = memCopy.remaining;
        eventContext->AppMemory.limit = memCopy.limit;
        eventContext->AppMemory.level = KSCrashAppMemoryStateToString((KSCrashAppMemoryState)memCopy.level).UTF8String;
        eventContext->AppMemory.timestamp = memCopy.timestamp;
        eventContext->AppMemory.state = kscm_app_transition_state_to_string(memCopy.state).UTF8String;
    }
}

static NSDictionary<NSString *, id> *kscm_memory_serialize(KSCrash_Memory *const memory)
{
    return @{
        @KSCrashField_MemoryFootprint: @(memory->footprint),
        @KSCrashField_MemoryRemaining: @(memory->remaining),
        @KSCrashField_MemoryLimit: @(memory->limit),
        @KSCrashField_MemoryPressure: KSCrashAppMemoryStateToString((KSCrashAppMemoryState)memory->pressure),
        @KSCrashField_MemoryLevel: KSCrashAppMemoryStateToString((KSCrashAppMemoryState)memory->level),
        @KSCrashField_Timestamp: @(memory->timestamp),
        @KSCrashField_AppTransitionState: kscm_app_transition_state_to_string(memory->state),
    };
}

/**
 here we check to see if the previous run was an OOM
 if it was, we load up the report created in the previous
 session and modify it, save it out to the reports location,
 and let the system run its course.
 */
static void kscm_memory_check_for_oom_in_previous_session(void)
{
    // And OOM should be the last thng we check for. For example,
    // If memory is critical but before being jetisoned we encounter
    // a programming error and receiving a Mach event or signal that
    // indicates a crash, we should process that on startup and ignore
    // and indication of an OOM.
    bool userPerceivedOOM = NO;
    if (ksmemory_previous_session_was_terminated_due_to_memory(&userPerceivedOOM)) {
        
        // We only report an OOM that the user might have seen.
        // Ignore this check if we want to report all OOM, foreground and background.
        if (userPerceivedOOM) {
            NSURL *url = kscm_memory_oom_breadcrumb_URL();
            const char *reportContents = kscrash_readReportAtPath(url.path.UTF8String);
            if (reportContents) {
                
                NSData *data = [NSData dataWithBytes:reportContents length:strlen(reportContents)];
                NSMutableDictionary *json = [[NSJSONSerialization JSONObjectWithData:data options:NSJSONReadingMutableContainers|NSJSONReadingMutableLeaves error:nil] mutableCopy];
                
                if (json) {
                    json[@KSCrashField_System][@KSCrashField_AppMemory] = kscm_memory_serialize(&g_previousSessionMemory);
                    json[@KSCrashField_Report][@KSCrashField_Timestamp] = @(g_previousSessionMemory.timestamp);
                    json[@KSCrashField_Crash][@KSCrashField_Error][@KSCrashExcType_MemoryTermination] =kscm_memory_serialize(&g_previousSessionMemory);
                    json[@KSCrashField_Crash][@KSCrashField_Error][@KSCrashExcType_Mach] = nil;
                    json[@KSCrashField_Crash][@KSCrashField_Error][@KSCrashExcType_Signal] = @{
                        @KSCrashField_Signal: @(SIGKILL),
                        @KSCrashField_Name: @"SIGKILL",
                    };
                    
                    data = [NSJSONSerialization dataWithJSONObject:json options:NSJSONWritingPrettyPrinted error:nil];
                    kscrash_addUserReport((const char *)data.bytes, (int)data.length);
                }
                free((void *)reportContents);
            }
        }
    }
    
    // remove the old breadcrumb oom file
    unlink(kscm_memory_oom_breadcrumb_URL().path.UTF8String);
}

/**
 This is called after all monitors are enabled.
 */
static void notifyPostSystemEnable(void)
{
    if (g_hasPostEnable) {
        return;
    }
    g_hasPostEnable = 1;
    
    kscm_memory_check_for_oom_in_previous_session();

    if (g_isEnabled)
    {
        ksmemory_write_possible_oom();
        g_memoryTracker = [[MemoryTracker alloc] init];
    }
}

KSCrashMonitorAPI* kscm_memory_getAPI(void)
{
    static KSCrashMonitorAPI api =
    {
        .setEnabled = setEnabled,
        .isEnabled = isEnabled,
        .addContextualInfoToEvent = addContextualInfoToEvent,
        .notifyPostSystemEnable = notifyPostSystemEnable,
    };
    return &api;
}

/**
 Read the previous sessions memory data.
 */
static void ksmemory_read(const char* path)
{
    int fd = open(path, O_RDONLY, 0644);
    if (fd == -1) {
        unlink(path);
        return;
    }
    
    size_t size = sizeof(KSCrash_Memory);
    KSCrash_Memory memory = {};
    if (!ksfu_readBytesFromFD(fd, (char *)&memory, (int)size)) {
        close(fd);
        unlink(path);
        return;
    }
    
    // validate some of the data before doing anything with it.
    
    // check the timestamp, let's say it's valid for the last week
    // do we really want crash reports older than a week anyway??
    const uint64_t kUS_in_day = 8.64e+10;
    const uint64_t kUS_in_week = kUS_in_day * 7;
    uint64_t now = ksdate_microseconds();
    if (memory.timestamp <= 0 || memory.timestamp == INT64_MAX || memory.timestamp < now - kUS_in_week) {
        return;
    }
    
    // check pressure and level are in ranges
    if (memory.level > KSCrashAppMemoryStateTerminal) {
        return;
    }
    if (memory.pressure > KSCrashAppMemoryStateTerminal) {
        return;
    }
    
    // check app transition state
    if (memory.state > KSCrash_ApplicationTransitionStateExiting) {
        return;
    }
    
    // Footprint and remaining should always = limit
    if (memory.footprint + memory.remaining != memory.limit) {
        return;
    }
    
    // if we're at max, we likely overflowed or set a negative value,
    // in any case, we're counting this as a possible error and bailing.
    if (memory.footprint == UINT64_MAX) {
        return;
    }
    if (memory.remaining == UINT64_MAX) {
        return;
    }
    if (memory.limit == UINT64_MAX) {
        return;
    }
    
    // Fatal will onyl ever be 0 or 1, otherwise we bail.
    if (memory.fatal > 1) {
        return;
    }
    
    g_previousSessionMemory = memory;
    
    close(fd);
    unlink(path);
}

/**
 Mapping memory to a file on disk. This allows us to simply treat the location
 in memory as a structure and the kernel will ensure it is on disk. This is also
 crash resistant.
 */
static void ksmemory_map(const char* path)
{
    void *ptr = ksfu_mmap(path, sizeof(KSCrash_Memory));
    if (!ptr) {
        return;
    }
    
    g_memory = (KSCrash_Memory *)ptr;
    KSCrashAppMemory *memory = g_memoryTracker.memory;
    
    _ks_memory_update(^(KSCrash_Memory *mem) {
        *mem = (KSCrash_Memory){
            .footprint = memory.footprint,
            .remaining = memory.remaining,
            .pressure = (uint8_t)memory.pressure,
            .level = (uint8_t)memory.level,
            .limit = memory.limit,
            .timestamp = ksdate_microseconds(),
            .state = g_AppStateTracker.transitionState,
            .fatal = 0,
        };
    });
}

/**
 What we're doing here is writing a file out that can be reused
 on restart if the data shows us there was a memory issue.
 
 If an OOM did happen, we'll modify this file
 (see `kscm_memory_check_for_oom_in_previous_session`),
 then write it back out using the normal writing procedure to write reports. This
 leads to the system seeing the report as if it had always been there and will
 then report an OOM.
 */
static void ksmemory_write_possible_oom(void)
{
    NSURL *reportURL = kscm_memory_oom_breadcrumb_URL();
    const char *reportPath = reportURL.path.UTF8String;
    
    //kscm_notifyFatalExceptionCaptured(false);
    
    KSMC_NEW_CONTEXT(machineContext);
    ksmc_getContextForThread(ksthread_self(), machineContext, false);
    KSStackCursor stackCursor;
    kssc_initWithMachineContext(&stackCursor, KSSC_MAX_STACK_DEPTH, machineContext);
    
    char eventID[37] = {0};
    ksid_generate(eventID);
    
    KSCrash_MonitorContext context;
    memset(&context, 0, sizeof(context));
    context.crashType = KSCrashMonitorTypeMemoryTermination;
    context.eventID = eventID;
    context.registersAreValid = false;
    context.offendingMachineContext = machineContext;
    context.currentSnapshotUserReported = true;
    
    // we don't need all the images, we have no stack
    context.omitBinaryImages = true;
    
    // _reportPath_ only valid within this scope
    context.reportPath = reportPath;

    kscm_handleException(&context);
}

void ksmemory_initialize(const char* installPath)
{
    g_installURL = [NSURL fileURLWithPath:@(installPath)];
    NSURL *memoryURL = [[g_installURL URLByAppendingPathComponent:@"Data"] URLByAppendingPathComponent:@"memory"];
    const char *path = memoryURL.path.UTF8String;
    
    // load up the old data
    ksmemory_read(path);
    
    // map new data
    ksmemory_map(path);
}

bool ksmemory_previous_session_was_terminated_due_to_memory(bool *userPerceptible)
{
    // If we had any kind of fatal, even if the data says an OOM, it wasn't an OOM.
    // The idea is that we could have been very close to an OOM then some
    // exception/event occured that terminated/crashed the app. We don't want to report
    // that as an OOM.
    if (g_previousSessionMemory.fatal) {
        return NO;
    }
    
    // We might care if the user might have seen the OOM
    if (userPerceptible) {
        *userPerceptible = ksapp_transition_state_is_user_perceptible(g_previousSessionMemory.state);
    }
    
    // level or pressure is critical++
    return g_previousSessionMemory.level >= KSCrashAppMemoryStateCritical ||
            g_previousSessionMemory.pressure >= KSCrashAppMemoryStateCritical;
}

bool ksapp_transition_state_is_user_perceptible(KSCrash_ApplicationTransitionState state)
{
    switch (state) {
        case KSCrash_ApplicationTransitionStateStartupPrewarm:
        case KSCrash_ApplicationTransitionStateBackground:
        case KSCrash_ApplicationTransitionStateTerminating:
        case KSCrash_ApplicationTransitionStateExiting:
            return NO;
            
        case KSCrash_ApplicationTransitionStateStartup:
        case KSCrash_ApplicationTransitionStateLaunching:
        case KSCrash_ApplicationTransitionStateForegrounding:
        case KSCrash_ApplicationTransitionStateActive:
        case KSCrash_ApplicationTransitionStateDeactivating:
            return YES;
    }
    return NO;
}
