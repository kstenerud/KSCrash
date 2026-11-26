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
#import "KSCrashAppStateTracker+Private.h"

#import "KSCrashHostKind.h"
#import "KSCrashNotificationNames.h"

#import <Foundation/Foundation.h>
#import <os/lock.h>

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
        _isAppExtension = kshostkind_current() == KSCrashHostKindExtension;
        // A watch app's application object is a UIApplication subclass posting the same
        // notifications. A macOS process has none.
        _applicationClass = (Class<KSCrashApplicationReading>)NSClassFromString(@"UIApplication");
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

    // Deliver the current state so the observer doesn't miss transitions
    // that already happened (e.g. on macOS, Active is set during start()
    // before any observers are registered). Dispatch async to avoid
    // re-entering the caller while still inside addObserverWithBlock:.
    // The state is read when the block fires, not captured here: real
    // transitions deliver synchronously, so one can land before this runs,
    // and replaying a registration-time snapshot would overwrite it.
    __weak typeof(self) weakSelf = self;
    dispatch_async(dispatch_get_main_queue(), ^{
        typeof(self) strongSelf = weakSelf;
        if (strongSelf != nil) {
            ((KSCrashAppStateTrackerObserverBlock)heapBlock)(strongSelf.transitionState);
        }
    });

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
    [self _moveToTransitionState:transitionState
                            when:^BOOL(__unused KSCrashAppTransitionState current) {
                                return YES;
                            }];
}

// The state changes only when the current state is `expected`, checked under the same lock as the
// change, so a value read earlier cannot overwrite a transition that arrived since.
- (void)_setTransitionState:(KSCrashAppTransitionState)transitionState
           ifCurrentStateIs:(KSCrashAppTransitionState)expected
{
    [self _moveToTransitionState:transitionState
                            when:^BOOL(KSCrashAppTransitionState current) {
                                return current == expected;
                            }];
}

// The one place the state changes. `shouldMove` is asked under the lock, with the current state;
// observers are called after the lock is released, and only when the state changed. `shouldMove`
// must not reach back into the tracker: the lock is not recursive, and locking it again on the
// thread that holds it terminates the process.
- (void)_moveToTransitionState:(KSCrashAppTransitionState)transitionState
                          when:(BOOL(NS_NOESCAPE ^)(KSCrashAppTransitionState current))shouldMove
{
    NSArray<KSCrashAppStateTrackerObserverBlock> *observers = nil;
    os_unfair_lock_lock(&_lock);
    if (_transitionState != transitionState && shouldMove(_transitionState)) {
        _transitionState = transitionState;
        [_observers compact];
        observers = [_observers allObjects];
    }
    os_unfair_lock_unlock(&_lock);
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

    // An app extension follows its extension host, the process presenting it, which is what the
    // user sees. One that nothing presents gets no host notifications at all, so an extension is
    // active from the start, set before observing so a transition cannot be overwritten.
    if (_isAppExtension) {
        [self _setTransitionState:KSCrashAppTransitionStateActive];
        _registrations = [self _observeExtensionHost];
        return;
    }

    if (_applicationClass == Nil) {
        // Nothing in this process posts application transitions, so it is active for its whole run,
        // which is what reports an OOM.
        [self _setTransitionState:KSCrashAppTransitionStateActive];
        return;
    }

    _registrations = [self _observeApplication];
    // Before UIApplicationMain there is no application object yet, and no launch notification has
    // been posted for the observers to miss. Its state, read on the run loop's first turn, is
    // background whatever the launch turns out to be, so it is not read at all.
    if (NSThread.isMainThread && [_applicationClass sharedApplication] == nil) {
        return;
    }
    [self _adoptApplicationStateFrom:self.transitionState afterACallout:NO];
}

- (NSArray<id<NSObject>> *)_observeApplication
{
    __weak typeof(self) weakMe = self;
    return @[
        OBSERVE(_center, KSApplicationDidFinishLaunchingNotification, { [weakMe _didFinishLaunching]; }),
        OBSERVE(_center, KSApplicationWillEnterForegroundNotification,
                { [weakMe _setTransitionState:KSCrashAppTransitionStateForegrounding]; }),
        OBSERVE(_center, KSApplicationDidBecomeActiveNotification,
                { [weakMe _setTransitionState:KSCrashAppTransitionStateActive]; }),
        OBSERVE(_center, KSApplicationWillResignActiveNotification,
                { [weakMe _setTransitionState:KSCrashAppTransitionStateDeactivating]; }),
        OBSERVE(_center, KSApplicationDidEnterBackgroundNotification,
                { [weakMe _setTransitionState:KSCrashAppTransitionStateBackground]; }),
        OBSERVE(_center, KSApplicationWillTerminateNotification,
                { [weakMe _setTransitionState:KSCrashAppTransitionStateTerminating]; }),
    ];
}

// A launch into the background (a location update, a fetch) never gets a foreground notification,
// so without this it would stay Launching, which is user perceptible, for its whole run. Reading
// the state at the launch notification cannot tell: a scene-based app reads background there on a
// foreground launch too. By the main queue's next turn a foreground launch has had its scene enter
// the foreground, moving the state on, and the guard drops the read; a background launch still
// reads background (probed on iOS 27, both ways). If a foreground launch ever reached that turn
// before its scene entered the foreground, it would show Background until the scene's
// notification arrived.
- (void)_didFinishLaunching
{
    [self _setTransitionState:KSCrashAppTransitionStateLaunching];
    __weak typeof(self) weakMe = self;
    dispatch_async(dispatch_get_main_queue(), ^{
        typeof(self) strongMe = weakMe;
        // A stopped tracker no longer follows the application.
        if (strongMe == nil || strongMe->_registrations == nil) {
            return;
        }
        id<KSCrashApplicationReading> application = [strongMe->_applicationClass sharedApplication];
        if (application.applicationState == KSCrashApplicationStateBackground) {
            [strongMe _setTransitionState:KSCrashAppTransitionStateBackground
                         ifCurrentStateIs:KSCrashAppTransitionStateLaunching];
        }
    });
}

- (NSArray<id<NSObject>> *)_observeExtensionHost
{
    __weak typeof(self) weakMe = self;
    // No Terminating equivalent exists; atexit_b in start handles Exiting.
    return @[
        OBSERVE(_center, KSExtensionHostDidBecomeActiveNotification,
                { [weakMe _setTransitionState:KSCrashAppTransitionStateActive]; }),
        OBSERVE(_center, KSExtensionHostWillResignActiveNotification,
                { [weakMe _setTransitionState:KSCrashAppTransitionStateDeactivating]; }),
        OBSERVE(_center, KSExtensionHostDidEnterBackgroundNotification,
                { [weakMe _setTransitionState:KSCrashAppTransitionStateBackground]; }),
        OBSERVE(_center, KSExtensionHostWillEnterForegroundNotification,
                { [weakMe _setTransitionState:KSCrashAppTransitionStateForegrounding]; }),
    ];
}

// The tracker starts on first access, which is normally install, and an app can install after it
// has launched, when the notifications that would have moved it on have already been posted. So
// start takes the application's current state once, after observing, and only while the state is
// still the one start saw: a notification that arrived in between wins.
//
// The read is made only on the main thread, from a running main run loop. `applicationState`
// belongs to the main thread, and install can run on any thread. A scene-based app, and a watch app,
// runs its whole launch, didFinishLaunching and UIApplicationDidFinishLaunchingNotification
// included, before the main run loop starts, reading background on its way to the foreground. A
// block performed on the main run loop waits for it to run, so the read made there comes after the
// launch notifications have moved the state on, and the guard below drops it. Until the read is
// made, readers see the starting state.
- (void)_adoptApplicationStateFrom:(KSCrashAppTransitionState)startState afterACallout:(BOOL)afterACallout
{
    __weak typeof(self) weakMe = self;
    CFRunLoopRef mainRunLoop = CFRunLoopGetMain();
    CFStringRef performModes = kCFRunLoopCommonModes;

    // A run loop that is not running has no current mode.
    CFStringRef currentMode = CFRunLoopCopyCurrentMode(mainRunLoop);
    bool mainRunLoopIsRunning = currentMode != NULL;
    if (currentMode != NULL) {
        CFRelease(currentMode);
    }
    if (!NSThread.isMainThread || !mainRunLoopIsRunning) {
        CFRunLoopPerformBlock(mainRunLoop, performModes, ^{
            [weakMe _adoptApplicationStateFrom:startState afterACallout:YES];
        });
        CFRunLoopWakeUp(mainRunLoop);
        return;
    }

    id<KSCrashApplicationReading> application = [_applicationClass sharedApplication];
    if (application == nil) {
        // No application object: nothing has launched it, so the starting state is the truth.
        return;
    }
    KSCrashApplicationState applicationState = application.applicationState;

    // An app without scenes launches inside one callout of the running main run loop and reads
    // inactive throughout, which looks the same as an interruption. UIKit posts
    // UIApplicationDidFinishLaunchingNotification in that same callout, and a block performed on the
    // main run loop runs only once the callout has returned. So an inactive read waits for the
    // current callout once: in a launch, the notification has moved the state on by then and the
    // guard below drops the read.
    if (applicationState == KSCrashApplicationStateInactive && !afterACallout) {
        CFRunLoopPerformBlock(mainRunLoop, performModes, ^{
            [weakMe _adoptApplicationStateFrom:startState afterACallout:YES];
        });
        CFRunLoopWakeUp(mainRunLoop);
        return;
    }

    KSCrashAppTransitionState adopted = ksapp_transitionStateForApplicationState(applicationState, startState);
    [self _setTransitionState:adopted ifCurrentStateIs:startState];
}

KSCrashAppTransitionState ksapp_transitionStateForApplicationState(KSCrashApplicationState applicationState,
                                                                   KSCrashAppTransitionState currentState)
{
    switch (applicationState) {
        case KSCrashApplicationStateActive:
            return KSCrashAppTransitionStateActive;

        case KSCrashApplicationStateBackground:
            return KSCrashAppTransitionStateBackground;

        case KSCrashApplicationStateInactive:
            // On screen but not active: either being interrupted (an alert, Control Center) or
            // coming back from the background, and UIKit does not say which. Deactivating is the
            // likelier one for an app found that way after launch. Both are user perceptible, and
            // the next notification corrects the label.
            return KSCrashAppTransitionStateDeactivating;

        default:
            return currentState;
    }
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
