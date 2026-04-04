//
//  KSCrashCPUTracker.h
//
//  Created by Alexander Cohen on 2026-03-29.
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

#import <Foundation/Foundation.h>

#include "KSCrashNamespace.h"

NS_ASSUME_NONNULL_BEGIN

/** CPU state based on sustained usage over sliding windows. */
typedef NS_ENUM(NSUInteger, KSCrashCPUState) {
    /** CPU usage is within normal limits. */
    KSCrashCPUStateNormal = 0,
    /** Sustained CPU usage has reached the level that triggers an EXC_RESOURCE report. */
    KSCrashCPUStateWarning,
    /** Sustained CPU usage has reached the level at which the system will terminate the app. */
    KSCrashCPUStateCritical,
} NS_SWIFT_NAME(CPUState);

/** Returns a string for the given CPU state ("normal", "warning", "critical").
 *  Async-signal-safe. */
FOUNDATION_EXPORT const char *KSCrashCPUStateToString(KSCrashCPUState state) NS_SWIFT_NAME(CPUState.cString(self:));

@class KSCrashCPU;

typedef NS_OPTIONS(NSUInteger, KSCrashCPUTrackerChangeType) {
    KSCrashCPUTrackerChangeTypeNone = 0,
    /** The CPU state (normal/warning/critical) changed since the last update. */
    KSCrashCPUTrackerChangeTypeState = 1 << 0,
    /** CPU usage values were updated. */
    KSCrashCPUTrackerChangeTypeUsage = 1 << 1,
} NS_SWIFT_NAME(CPUTrackerChangeType);

typedef void (^KSCrashCPUTrackerObserverBlock)(KSCrashCPU *cpu, KSCrashCPUTrackerChangeType changes,
                                               KSCrashCPUState previousState)
    NS_SWIFT_UNAVAILABLE("Use Swift closures instead!");

/** Tracks CPU usage over sliding windows and classifies the current state. */
NS_SWIFT_NAME(CPUTracker)
@interface KSCrashCPUTracker : NSObject

- (instancetype)init NS_UNAVAILABLE;
+ (instancetype)new NS_UNAVAILABLE;

@property(class, atomic, readonly) KSCrashCPUTracker *sharedInstance NS_SWIFT_NAME(shared);

/** The current CPU state classification. */
@property(atomic, readonly) KSCrashCPUState state;

/** Number of active CPU cores on this device. */
@property(nonatomic, readonly) uint8_t coreCount;

/** A copy of the most recent CPU snapshot, or nil if no data has been collected. */
@property(nonatomic, readonly, copy, nullable) KSCrashCPU *currentCPU;

/** Adds a block-based observer that is called periodically with the latest snapshot.
 *  @return An opaque token. The observer is removed when this token is deallocated.
 */
- (id)addObserverWithBlock:(KSCrashCPUTrackerObserverBlock)block;

@end

/** Immutable snapshot of CPU state at one instant. */
NS_SWIFT_NAME(CPU)
@interface KSCrashCPU : NSObject <NSCopying>

- (instancetype)init NS_UNAVAILABLE;
+ (instancetype)new NS_UNAVAILABLE;

/** The CPU state classification at the time of this snapshot. */
@property(readonly, nonatomic, assign) KSCrashCPUState state;

/** User-space CPU usage in permil of one core (0–N*1000 where N is the core count). */
@property(readonly, nonatomic, assign) uint16_t usageUser;

/** Kernel-space CPU usage in permil of one core (0–N*1000 where N is the core count). */
@property(readonly, nonatomic, assign) uint16_t usageSystem;

/** Process thread count at the time of this snapshot. */
@property(readonly, nonatomic, assign) uint16_t threadCount;

/** Average CPU usage over the active threshold window as a fraction of total capacity.
 *  0.0 when state is Normal. 1.0 means all cores fully utilized. */
@property(readonly, nonatomic, assign) double averageUsageInWindow;

/** CPU time accumulated in the active threshold window.
 *  0 when state is Normal. */
@property(readonly, nonatomic, assign) NSTimeInterval cpuTimeInWindow;

/** Wall time spanned by the active threshold window.
 *  0 when state is Normal. */
@property(readonly, nonatomic, assign) NSTimeInterval wallTimeInWindow;

/** Monotonic timestamp (nanoseconds) when this snapshot was taken. */
@property(readonly, nonatomic, assign) uint64_t timestampNs;

@end

NS_ASSUME_NONNULL_END
