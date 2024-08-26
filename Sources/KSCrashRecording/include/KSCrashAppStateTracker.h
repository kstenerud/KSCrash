//
//  KSCrashAppStateTracker.h
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
#import <Foundation/Foundation.h>
#import "KSCrashAppTransitionState.h"

NS_ASSUME_NONNULL_BEGIN

/**
 * KSCrashAppStateTracker
 *
 * This system tracks the app state, but also gives insight into the transitions
 * from launch to termination. One reason why this is useful is that when a user
 * brings a running process to the foreground, it goes through an animation from
 * background to foreground that is not accounted for in UIApplicationState but
 * is still visible to users. If the app crashes or is temrinated during that time, the
 * application state is `UIApplicationStateBackground` which is usually not
 * accounted for in crash systems. This newer method with transitions included in
 * the state is much more complete and allows products to be much more reliable
 * and handle areas of the app that are very important to users but rarely handled
 * by apps.
 *
 * We'll keep it private for now until it is integrated with `KSCrashMonitor_AppState`.
 */

typedef void (^KSCrashAppStateTrackerObserverBlock)(KSCrashAppTransitionState transitionState)
    NS_SWIFT_UNAVAILABLE("Use Swift closures instead!");

@protocol KSCrashAppStateTrackerObserving;

NS_SWIFT_NAME(AppStateTracker)
@interface KSCrashAppStateTracker : NSObject

/**
 * The shared tracker. Use this unless you absolutely need your own tracker,
 * at which point you can simply allocate your own.
 */
@property(class, readonly) KSCrashAppStateTracker *sharedInstance NS_SWIFT_NAME(shared);

- (instancetype)initWithNotificationCenter:(NSNotificationCenter *)notificationCenter NS_DESIGNATED_INITIALIZER;

@property(atomic, readonly) KSCrashAppTransitionState transitionState;

/**
 * Adds an observer that implements the _KSCrashAppStateTrackerObserving_ protocol.
 * You do not need to remove the observer as it is held weakly.
 */
- (void)addObserver:(id<KSCrashAppStateTrackerObserving>)observer;

/**
 * Adds a block based observer.
 *
 *@return An object you must hold on to in order to remove the observation at a later point.
 */
- (id<KSCrashAppStateTrackerObserving>)addObserverWithBlock:(KSCrashAppStateTrackerObserverBlock)block;

/** Removes an observer */
- (void)removeObserver:(id<KSCrashAppStateTrackerObserving>)observer;

/**
 * Start/Stop
 *
 * WARNING: Don't call these on the shared tracker.
 */
- (void)start;
- (void)stop;

@end

/** Implement this and add yourself to a tracker to observer transitions */
NS_SWIFT_NAME(AppStateTrackerObserving)
@protocol KSCrashAppStateTrackerObserving <NSObject>
- (void)appStateTracker:(KSCrashAppStateTracker *)tracker didTransitionToState:(KSCrashAppTransitionState)state;
@end

NS_ASSUME_NONNULL_END
