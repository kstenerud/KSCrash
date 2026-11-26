//
//  KSCrashAppStateTracker+Private.h
//
//  Created by Alexander Cohen on 2026-11-21.
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

#import "KSCrashAppStateTracker.h"

NS_ASSUME_NONNULL_BEGIN

/** `UIApplicationState`'s values, which the tracker reads without importing UIKit. */
typedef NS_ENUM(NSInteger, KSCrashApplicationState) {
    KSCrashApplicationStateActive = 0,
    KSCrashApplicationStateInactive = 1,
    KSCrashApplicationStateBackground = 2,
};

/** The part of `UIApplication` the tracker reads. The class is looked up by name and messaged
 *  through this declaration, so the tracker never imports UIKit.
 */
@protocol KSCrashApplicationReading <NSObject>
@property(class, nonatomic, readonly, nullable) id<KSCrashApplicationReading> sharedApplication;
@property(nonatomic, readonly) KSCrashApplicationState applicationState;
@end

@interface KSCrashAppStateTracker ()

/** Whether this process is an app extension, which makes `start` follow its extension host's
 *  transitions instead of the application's. Decided at init from the process's host kind; tests set
 *  it before `start`, since a test runner is never an extension.
 */
@property(nonatomic) BOOL isAppExtension;

/** The process's `UIApplication` class, or Nil where there is none, which makes `start` treat the
 *  process as active for its whole run. Looked up at init; tests set it before `start`.
 */
@property(nonatomic, nullable) Class<KSCrashApplicationReading> applicationClass;

@end

/** The state the tracker's `start` takes from the application when it finds one already running.
 *
 * @param applicationState The application's state, read from a running main run loop.
 * @param currentState The tracker's state before `start` read the application.
 * @return The state to move to, or `currentState` when the application's state does not say.
 */
KSCrashAppTransitionState ksapp_transitionStateForApplicationState(KSCrashApplicationState applicationState,
                                                                   KSCrashAppTransitionState currentState);

NS_ASSUME_NONNULL_END
