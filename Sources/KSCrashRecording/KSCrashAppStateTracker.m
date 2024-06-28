//
//  KSCrashAppStateTracker.m
//
//  Created by Alexander Cohen on 2024-05-20.
//
//  Copyright (c) 2024 Alexander Cohen. All rights reserved.
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
#import "KSCrashAppStateTracker.h"

#import "KSSystemCapabilities.h"

#import <Foundation/Foundation.h>
#import <os/lock.h>

#if KSCRASH_HAS_UIAPPLICATION
#import <UIKit/UIKit.h>
#endif

const char *ksapp_transitionStateToString(KSCrashAppTransitionState state)
{
    switch (state) {
        case KSCrashAppTransitionStateStartup:
            return "startup";
        case KSCrashAppTransitionStateStartupPrewarm:
            return "prewarm";
        case KSCrashAppTransitionStateActive:
            return "active";
        case KSCrashAppTransitionStateLaunching:
            return "launching";
        case KSCrashAppTransitionStateBackground:
            return "background";
        case KSCrashAppTransitionStateTerminating:
            return "terminating";
        case KSCrashAppTransitionStateExiting:
            return "exiting";
        case KSCrashAppTransitionStateDeactivating:
            return "deactivating";
        case KSCrashAppTransitionStateForegrounding:
            return "foregrounding";
    }
    return "unknown";
}

bool ksapp_transitionStateIsUserPerceptible(KSCrashAppTransitionState state)
{
    switch (state) {
        case KSCrashAppTransitionStateStartupPrewarm:
        case KSCrashAppTransitionStateBackground:
        case KSCrashAppTransitionStateTerminating:
        case KSCrashAppTransitionStateExiting:
            return NO;

        case KSCrashAppTransitionStateStartup:
        case KSCrashAppTransitionStateLaunching:
        case KSCrashAppTransitionStateForegrounding:
        case KSCrashAppTransitionStateActive:
        case KSCrashAppTransitionStateDeactivating:
            return YES;
    }
    return NO;
}

@interface KSCrashAppStateTrackerBlockObserver : NSObject <KSCrashAppStateTrackerObserving>

@property(nonatomic, copy) KSCrashAppStateTrackerObserverBlock block;
@property(nonatomic, weak) id<KSCrashAppStateTrackerObserving> object;

@property(nonatomic, weak) KSCrashAppStateTracker *tracker;

- (BOOL)shouldReap;

@end

@implementation KSCrashAppStateTrackerBlockObserver

- (void)appStateTracker:(nonnull KSCrashAppStateTracker *)tracker
    didTransitionToState:(KSCrashAppTransitionState)transitionState
{
    KSCrashAppStateTrackerObserverBlock block = self.block;
    if (block) {
        block(transitionState);
    }

    id<KSCrashAppStateTrackerObserving> object = self.object;
    if (object) {
        [object appStateTracker:self.tracker didTransitionToState:transitionState];
    }
}

- (BOOL)shouldReap
{
    return self.block == nil && self.object == nil;
}

@end

@interface KSCrashAppStateTracker () {
    NSNotificationCenter *_center;
    NSArray<id<NSObject>> *_registrations;

    // transition state and observers protected by the lock
    os_unfair_lock _lock;
    KSCrashAppTransitionState _transitionState;
    NSMutableArray<id<KSCrashAppStateTrackerObserving>> *_observers;
}
@end

@implementation KSCrashAppStateTracker

+ (void)load
{
    // to work well, we need this to run as early as possible.
    (void)[KSCrashAppStateTracker sharedInstance];
}

+ (instancetype)sharedInstance
{
    static KSCrashAppStateTracker *sTracker;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sTracker = [[KSCrashAppStateTracker alloc] init];
        [sTracker start];
    });
    return sTracker;
}

- (instancetype)init
{
    return [self initWithNotificationCenter:NSNotificationCenter.defaultCenter];
}

- (instancetype)initWithNotificationCenter:(NSNotificationCenter *)notificationCenter
{
    if (self = [super init]) {
        _lock = OS_UNFAIR_LOCK_INIT;
        _observers = [NSMutableArray array];
        _center = notificationCenter;
        _registrations = nil;

        BOOL isPrewarm = [NSProcessInfo.processInfo.environment[@"ActivePrewarm"] boolValue];
        _transitionState = isPrewarm ? KSCrashAppTransitionStateStartupPrewarm : KSCrashAppTransitionStateStartup;
    }
    return self;
}

- (void)dealloc
{
    [self stop];
}

// Observers are either an object passed in that
// implements `KSCrashAppStateTrackerObserving` or a block.
// Both will be wrapped in a `KSCrashAppStateTrackerBlockObserver`.
// if a block, then it'll simply call the block.
// If the object, we'll keep a weak reference to it.
// Objects will be reaped when their block and their object
// is nil.
// We'll reap on add and removal or any type of observer.
- (void)_locked_reapObserversOrObject:(id)object
{
    NSMutableArray *toRemove = [NSMutableArray array];
    for (KSCrashAppStateTrackerBlockObserver *obj in _observers) {
        if ((obj.object != nil && obj.object == object) || [obj shouldReap]) {
            [toRemove addObject:obj];
            obj.object = nil;
            obj.block = nil;
        }
    }
    [_observers removeObjectsInArray:toRemove];
}

- (void)_addObserver:(KSCrashAppStateTrackerBlockObserver *)observer
{
    os_unfair_lock_lock(&_lock);
    [_observers addObject:observer];
    [self _locked_reapObserversOrObject:nil];
    os_unfair_lock_unlock(&_lock);
}

- (void)addObserver:(id<KSCrashAppStateTrackerObserving>)observer
{
    KSCrashAppStateTrackerBlockObserver *obs = [[KSCrashAppStateTrackerBlockObserver alloc] init];
    obs.object = observer;
    obs.tracker = self;
    [self _addObserver:obs];
}

- (id<KSCrashAppStateTrackerObserving>)addObserverWithBlock:(KSCrashAppStateTrackerObserverBlock)block
{
    KSCrashAppStateTrackerBlockObserver *obs = [[KSCrashAppStateTrackerBlockObserver alloc] init];
    obs.block = [block copy];
    obs.tracker = self;
    [self _addObserver:obs];
    return obs;
}

- (void)removeObserver:(id<KSCrashAppStateTrackerObserving>)observer
{
    os_unfair_lock_lock(&_lock);

    // Observers added with a block
    if ([observer isKindOfClass:KSCrashAppStateTrackerBlockObserver.class]) {
        KSCrashAppStateTrackerBlockObserver *obs = (KSCrashAppStateTrackerBlockObserver *)observer;
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

- (KSCrashAppTransitionState)transitionState
{
    KSCrashAppTransitionState ret;
    {
        os_unfair_lock_lock(&_lock);
        ret = _transitionState;
        os_unfair_lock_unlock(&_lock);
    }
    return ret;
}

- (void)_setTransitionState:(KSCrashAppTransitionState)transitionState
{
    NSArray<id<KSCrashAppStateTrackerObserving>> *observers = nil;
    {
        os_unfair_lock_lock(&_lock);
        if (_transitionState != transitionState) {
            _transitionState = transitionState;
            observers = [_observers copy];
        }
        os_unfair_lock_unlock(&_lock);
    }

    for (id<KSCrashAppStateTrackerObserving> obs in observers) {
        [obs appStateTracker:self didTransitionToState:transitionState];
    }
}

#define OBSERVE(center, name, block) \
    [center addObserverForName:name object:nil queue:nil usingBlock:^(NSNotification * notification) block]

- (void)_exitCalled
{
    // _registrations is nil when the system is stopped
    if (!_registrations) {
        return;
    }
    [self _setTransitionState:KSCrashAppTransitionStateExiting];
}

- (void)start
{
    if (_registrations) {
        return;
    }

    __weak typeof(self) weakMe = self;

    // Register a normal `exit` callback so we don't think it's an OOM.
    atexit_b(^{
        [weakMe _exitCalled];
    });

#if KSCRASH_HAS_UIAPPLICATION

    // register all normal lifecycle events
    // in the future, we could also look at scene lifecycle
    // events but in reality, we don't actually need to,
    // it could just give us more granularity.
    _registrations = @[

        OBSERVE(_center, UIApplicationDidFinishLaunchingNotification,
                { [weakMe _setTransitionState:KSCrashAppTransitionStateLaunching]; }),
        OBSERVE(_center, UIApplicationWillEnterForegroundNotification,
                { [weakMe _setTransitionState:KSCrashAppTransitionStateForegrounding]; }),
        OBSERVE(_center, UIApplicationDidBecomeActiveNotification,
                { [weakMe _setTransitionState:KSCrashAppTransitionStateActive]; }),
        OBSERVE(_center, UIApplicationWillResignActiveNotification,
                { [weakMe _setTransitionState:KSCrashAppTransitionStateDeactivating]; }),
        OBSERVE(_center, UIApplicationDidEnterBackgroundNotification,
                { [weakMe _setTransitionState:KSCrashAppTransitionStateBackground]; }),
        OBSERVE(_center, UIApplicationWillTerminateNotification,
                { [weakMe _setTransitionState:KSCrashAppTransitionStateTerminating]; }),
    ];

#else
    // on other platforms that don't have UIApplication
    // we simply state that the app is active in order to report OOMs.
    [self _setTransitionState:KSCrashAppTransitionStateActive];
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
