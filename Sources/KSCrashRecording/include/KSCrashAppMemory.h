//
//  KSCrashAppMemory.h
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

/**
 * Application Memory
 *
 * There are two kinds of app memory handled here, LIMIT and PRESSURE.
 *
 * LIMIT
 * Limit (aka AppMemoryLevel) is the maximum amount of memory you can use by through
 * things like malloc, object allocations and so on (mostly heap). Once you hit this high-water
 * mark, the OS will terminate the application by sending it a SIGKILL signal. This is valid in
 * the foreground as well as the background.
 *
 * PRESSURE
 * Pressure (aka AppMemoryPressure) is how much the iOS ecosystem is pushing on the
 * current app to be a good memory citizen. Usually, when your app is in the foreground it
 * has a high priority thus doesn't get too much pressure. But there are exceptions such as
 * CarPlay apps, music apps and so on that can sometimes have a higher priority than the
 * foreground app, this is where pressure can come in very handy. That being said, pressure
 * is mostly useful in the background, it can help you not get your app jetsamed or simply
 * stay up longer for whatever reason you might have.
 *
 * My recommendation around memory pressure however is to have a robust app restoration
 * system and not bother too much with background memory, as long as your foreground
 * memory consumption is well handled.
 *
 * RECS
 * Follow the memory limit with an eagle eye. Make sure you act upon the changes as they
 * happen instead of all at once as with `didReceiveMemoryWarning`. Don't simple drop
 * everything you have in memory. Take it step by step. An good way to do this is to keep your
 * cache total cost limits in line with the memory limit.
 */
NS_ASSUME_NONNULL_BEGIN

/** Notification sent when the memory level changes. */
FOUNDATION_EXPORT NSNotificationName const KSCrashAppMemoryLevelChangedNotification NS_SWIFT_NAME(AppMemoryLevelChangedNotification);

/** Notification sent when the memory pressure changes. */
FOUNDATION_EXPORT NSNotificationName const KSCrashAppMemoryPressureChangedNotification NS_SWIFT_NAME(AppMemoryPressureChangedNotification);

/** Notification keys that hold new and old values in the _userInfo_ dictionary. */
typedef NSString *KSCrashAppMemoryKeys NS_TYPED_ENUM NS_SWIFT_NAME(AppMemoryKeys);
FOUNDATION_EXPORT KSCrashAppMemoryKeys const KSCrashAppMemoryNewValueKey NS_SWIFT_NAME(newValue);
FOUNDATION_EXPORT KSCrashAppMemoryKeys const KSCrashAppMemoryOldValueKey NS_SWIFT_NAME(oldValue);

/** The memory state for level and pressure. */
typedef NS_ENUM(NSUInteger, KSCrashAppMemoryState) {

    /** Everything is A-OK, go on with your business. */
    KSCrashAppMemoryStateNormal = 0,

    /** Things are starting to get heavy. */
    KSCrashAppMemoryStateWarn,

    /** Things are getting serious, allocations should be handled carefully. */
    KSCrashAppMemoryStateUrgent,

    /** At this point you are seconds away from being terminated.
     *  You likely just received or are about to receive a
     *  UIApplicationDidReceiveMemoryWarningNotification.
     */
    KSCrashAppMemoryStateCritical,

    /** You have been or will be terminated. Out-Of-Memory. SIGKILL. */
    KSCrashAppMemoryStateTerminal
} NS_SWIFT_NAME(AppMemoryState);

/**
 * Helpers to convert to and from pressure/level and strings.
 * `KSCrashAppMemoryStateToString` returns a `const char*`
 * because it needs to be async safe.
 */
FOUNDATION_EXPORT const char *KSCrashAppMemoryStateToString(KSCrashAppMemoryState state)
    NS_SWIFT_NAME(AppMemoryState.cString(self:));

FOUNDATION_EXPORT KSCrashAppMemoryState KSCrashAppMemoryStateFromString(NSString *const string)
    NS_SWIFT_NAME(AppMemoryState.fromString(_:));

/**
 * AppMemory is a simple container object for everything important on Apple platforms
 * surrounding memory.
 */
NS_SWIFT_NAME(AppMemory)
@interface KSCrashAppMemory : NSObject

- (instancetype)init NS_UNAVAILABLE;
+ (instancetype)new NS_UNAVAILABLE;

/** Footprint is the amount of memory used up against the memory limit (level). */
@property(readonly, nonatomic, assign) uint64_t footprint;

/**
 * Remaining is how much memory is left before the app is terminated.
 * same as `os_proc_available_memory`.
 * https://developer.apple.com/documentation/os/3191911-os_proc_available_memory
 */
@property(readonly, nonatomic, assign) uint64_t remaining;

/** The limi is the maximum amount of memory that can be used by this app,
 *  it's the value that if attained the app will be terminated.
 *  Do not cache this value as it can change at runtime (it's very very rare however).
 */
@property(readonly, nonatomic, assign) uint64_t limit;

/** The current memory level. */
@property(readonly, nonatomic, assign) KSCrashAppMemoryState level;

/** The current memory pressure. */
@property(readonly, nonatomic, assign) KSCrashAppMemoryState pressure;

/** True when the app is totally out of memory. */
@property(readonly, nonatomic, assign) BOOL isOutOfMemory;

@end

NS_ASSUME_NONNULL_END
