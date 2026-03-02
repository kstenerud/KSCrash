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

#if KSCRASH_HAS_NSEXTENSION
#import <WatchKit/WatchKit.h>
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
        default:
            return "unknown";
    }
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
        default:
            return NO;
    }
}

@interface KSCrashAppStateTracker () {
    NSNotificationCenter *_center;
    NSArray<id<NSObject>> *_registrations;

    // transition state and observers protected by the lock
    os_unfair_lock _lock;
    KSCrashAppTransitionState _transitionState;

    // weak objects are `KSCrashAppStateTrackerObserverBlock`'s
    NSPointerArray *_observers;
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
    if ((self = [super init])) {
        _lock = OS_UNFAIR_LOCK_INIT;
        _observers = [NSPointerArray weakObjectsPointerArray];
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

- (id)addObserverWithBlock:(KSCrashAppStateTrackerObserverBlock)block
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

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-implementations"

- (void)addObserver:(id<KSCrashAppStateTrackerObserving>)observer
{
    // Deprecated: wrap the protocol observer into a block observer.
    __weak id<KSCrashAppStateTrackerObserving> weakObserver = observer;
    __weak typeof(self) weakSelf = self;
    [self addObserverWithBlock:^(KSCrashAppTransitionState transitionState) {
        [weakObserver appStateTracker:weakSelf didTransitionToState:transitionState];
    }];
}

- (void)removeObserver:(__unused id<KSCrashAppStateTrackerObserving>)observer
{
    // Deprecated: block-based observers are removed automatically when set to nil.
}

#pragma clang diagnostic pop

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
    NSArray<KSCrashAppStateTrackerObserverBlock> *observers = nil;
    {
        os_unfair_lock_lock(&_lock);
        if (_transitionState != transitionState) {
            _transitionState = transitionState;
            [_observers compact];
            observers = [_observers allObjects];
        }
        os_unfair_lock_unlock(&_lock);
    }

    for (KSCrashAppStateTrackerObserverBlock obs in observers) {
        obs(transitionState);
    }
}

#define OBSERVE(center, name, block) \
    [center addObserverForName:name object:nil queue:nil usingBlock:^(__unused NSNotification * notification) block]

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

#elif KSCRASH_HAS_NSEXTENSION

    // watchOS extensions use NSExtensionHost* notifications for lifecycle.
    // No Terminating equivalent exists — atexit_b above handles Exiting.
    _registrations = @[
        OBSERVE(_center, NSExtensionHostDidBecomeActiveNotification,
                { [weakMe _setTransitionState:KSCrashAppTransitionStateActive]; }),
        OBSERVE(_center, NSExtensionHostWillResignActiveNotification,
                { [weakMe _setTransitionState:KSCrashAppTransitionStateDeactivating]; }),
        OBSERVE(_center, NSExtensionHostDidEnterBackgroundNotification,
                { [weakMe _setTransitionState:KSCrashAppTransitionStateBackground]; }),
        OBSERVE(_center, NSExtensionHostWillEnterForegroundNotification,
                { [weakMe _setTransitionState:KSCrashAppTransitionStateForegrounding]; }),
    ];

#else
    // on other platforms that don't have UIApplication
    // we simply state that the app is active in order to report OOMs.
    [self _setTransitionState:KSCrashAppTransitionStateActive];
#endif
}

- (void)stop
{
    NSArray<id<NSObject>> *registrations = [_registrations copy];
    _registrations = nil;
    for (id<NSObject> registration in registrations) {
        [_center removeObserver:registration];
    }
}

@end
