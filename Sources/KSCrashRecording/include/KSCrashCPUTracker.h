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

/** CPU state based on sustained usage over sliding windows.
 *
 *  Thresholds are derived from Apple's MetricKit CPU exception diagnostics:
 *  - Warning:  >50% average CPU over 180s → EXC_RESOURCE report
 *  - Critical: >80% average CPU over  60s → app killed by the system
 *
 *  These represent total CPU capacity (all cores combined), where 1.0 = 100%
 *  of all cores.
 */
typedef NS_ENUM(NSUInteger, KSCrashCPUState) {
    KSCrashCPUStateNormal = 0,
    KSCrashCPUStateWarning,
    KSCrashCPUStateCritical,
} NS_SWIFT_NAME(CPUState);

/** Returns a string for the given CPU state ("normal", "warning", "critical").
 *  Async-signal-safe. */
FOUNDATION_EXPORT const char *KSCrashCPUStateToString(KSCrashCPUState state) NS_SWIFT_NAME(CPUState.cString(self:));

@class KSCrashCPU;

typedef NS_OPTIONS(NSUInteger, KSCrashCPUTrackerChangeType) {
    KSCrashCPUTrackerChangeTypeNone = 0,
    KSCrashCPUTrackerChangeTypeState = 1 << 0,
    KSCrashCPUTrackerChangeTypeUsage = 1 << 1,
} NS_SWIFT_NAME(CPUTrackerChangeType);

typedef void (^KSCrashCPUTrackerObserverBlock)(KSCrashCPU *cpu, KSCrashCPUTrackerChangeType changes)
    NS_SWIFT_UNAVAILABLE("Use Swift closures instead!");

NS_SWIFT_NAME(CPUTracker)
@interface KSCrashCPUTracker : NSObject

@property(class, atomic, readonly) KSCrashCPUTracker *sharedInstance NS_SWIFT_NAME(shared);

@property(atomic, readonly) KSCrashCPUState state;

@property(nonatomic, readonly) uint8_t coreCount;

@property(nonatomic, readonly, nullable) KSCrashCPU *currentCPU;

/** Adds a block-based observer. Notified on every poll (5s).
 *  @return An object that when set to nil will remove the observer.
 */
- (id)addObserverWithBlock:(KSCrashCPUTrackerObserverBlock)block;

@end

/** Immutable snapshot of CPU state at one poll instant. */
NS_SWIFT_NAME(CPU)
@interface KSCrashCPU : NSObject

- (instancetype)init NS_UNAVAILABLE;
+ (instancetype)new NS_UNAVAILABLE;

@property(readonly, nonatomic, assign) KSCrashCPUState state;
@property(readonly, nonatomic, assign) uint16_t usageUser;    // permil of one core (last interval)
@property(readonly, nonatomic, assign) uint16_t usageSystem;  // permil of one core (last interval)
@property(readonly, nonatomic, assign) uint16_t threadCount;

/** Average CPU usage over the active threshold window (0.0–N.0 where 1.0 = one core). */
@property(readonly, nonatomic, assign) double averageUsageInWindow;

/** CPU seconds accumulated in the active threshold window. */
@property(readonly, nonatomic, assign) NSTimeInterval cpuTimeInWindow;

/** Wall seconds of the active threshold window. */
@property(readonly, nonatomic, assign) NSTimeInterval wallTimeInWindow;

@end

NS_ASSUME_NONNULL_END
