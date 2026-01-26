//
//  KSCrashHang.h
//
//  Created by Alexander Cohen on 2026-01-19.
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

/**
 * @brief Monitors for hangs and watchdog timeout terminations.
 *
 * ## Hangs
 *
 * A hang occurs when the main thread is blocked and cannot process user input
 * or update the UI. Even brief hangs degrade the user experience, making the app
 * feel sluggish or frozen.
 *
 * Apple categorizes hangs by duration:
 * - **Micro-hang**: 100-250ms - User may notice a slight delay
 * - **Hang**: 250ms+ - Noticeable stutter, app feels unresponsive
 * - **Severe hang**: 500ms+ - App appears frozen
 *
 * This monitor uses 250ms as the threshold to detect hangs, capturing the main
 * thread's stack trace when the run loop is blocked beyond this duration.
 *
 * ## Watchdog Terminations
 *
 * Apple enforces strict responsiveness requirements during
 * critical app transitions (launch, resume, suspend). If the main thread is
 * blocked too long, the system's watchdog terminates the app to protect the
 * user experience.
 *
 * Watchdog terminations are identified by the exception code `0x8badf00d`
 * ("ate bad food"). These are fatal crashes that occur without warning, leaving
 * no opportunity for the app to save state or report the issue through normal
 * crash handlers.
 *
 * By continuously monitoring the main thread and writing hang reports to disk,
 * this monitor ensures that if a watchdog termination occurs, a crash report
 * will already be on disk for the next launch.
 *
 * @see https://developer.apple.com/documentation/xcode/understanding-hangs-in-your-app
 * @see https://developer.apple.com/documentation/xcode/addressing-watchdog-terminations
 */

#ifndef HDR_KSCrashHang_h
#define HDR_KSCrashHang_h

#ifdef __cplusplus
extern "C" {
#endif

#include "KSCrashNamespace.h"

#ifdef __OBJC__

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/**
 * Describes the type of hang state change being reported to observers.
 */
typedef NS_ENUM(uint8_t, KSHangChangeType) {
    /** No change (placeholder value). */
    KSHangChangeTypeNone = 0,
    /** A new hang has been detected and a report is being generated. */
    KSHangChangeTypeStarted = 1,
    /** An ongoing hang's duration has been updated. */
    KSHangChangeTypeUpdated = 2,
    /** The hang has ended (main thread became responsive). */
    KSHangChangeTypeEnded = 3
} NS_SWIFT_NAME(HangChangeType);

/**
 * Block type for observing hang state changes.
 *
 * @param change The type of hang state change.
 * @param startTimestamp The monotonic timestamp (in nanoseconds) when the hang started.
 * @param endTimestamp The monotonic timestamp (in nanoseconds) of the current/end state.
 */
typedef void (^KSHangObserverBlock)(KSHangChangeType change, uint64_t startTimestamp, uint64_t endTimestamp)
    NS_SWIFT_UNAVAILABLE("Use Swift closures instead");

/** Registers an observer to be notified of hang state changes.
 *
 * The observer block will be called when:
 * - A hang is first detected (KSHangChangeTypeStarted)
 * - An ongoing hang's duration is updated (KSHangChangeTypeUpdated)
 * - A hang ends and the main thread becomes responsive (KSHangChangeTypeEnded)
 *
 * @note This function requires `KSCrashMonitorTypeWatchdog` to be enabled in your
 *       KSCrash configuration. If the watchdog monitor is not enabled, this function
 *       returns `nil` and no observations will occur.
 *
 * @param observer The block to call when hang state changes occur.
 * @return An opaque token object that keeps the observer registered, or `nil` if the
 *         watchdog monitor is not enabled. The observer remains registered as long as
 *         this token is retained. Release it to unregister the observer.
 */
id _Nullable kshang_addHangObserver(KSHangObserverBlock observer) NS_SWIFT_NAME(KSCrash.addHangObserver(_:));

NS_ASSUME_NONNULL_END

#endif

#ifdef __cplusplus
}
#endif

#endif  // HDR_KSCrashHang_h
