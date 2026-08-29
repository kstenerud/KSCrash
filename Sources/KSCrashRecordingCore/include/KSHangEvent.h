//
//  KSHangEvent.h
//
//  Created by Alexander Cohen on 2026-08-29.
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

#ifndef KSHangEvent_h
#define KSHangEvent_h

#include <CoreFoundation/CoreFoundation.h>
#include <stdint.h>

#include "KSCrashNamespace.h"

#ifdef __cplusplus
extern "C" {
#endif

/**
 * Describes the type of hang state change being reported.
 */
typedef CF_ENUM(uint8_t, KSHangChangeType) {
    /** No change (placeholder value). */
    KSHangChangeTypeNone = 0,
    /** A new hang has been detected and a report is being generated. */
    KSHangChangeTypeStarted = 1,
    /** An ongoing hang's duration has been updated. */
    KSHangChangeTypeUpdated = 2,
    /** The hang has ended (main thread became responsive). */
    KSHangChangeTypeEnded = 3,
} CF_SWIFT_NAME(HangChangeType);

/**
 * C function pointer type for observing hang state changes.
 *
 * @param change The type of hang state change.
 * @param startTimestamp Monotonic timestamp (ns) when the hang started.
 * @param endTimestamp Monotonic timestamp (ns) of the current/end state.
 */
typedef void (*KSHangEventCallback)(KSHangChangeType change, uint64_t startTimestamp, uint64_t endTimestamp);

/** Sets the single process-wide hang event callback, invoked from the hang
 * monitor's thread on every hang state change. The slot is owned by the
 * framework's hang event hub, and it is not public API.
 *
 * The callback must stay valid for the process lifetime; a replaced callback
 * may still receive an event already being dispatched.
 *
 * @return The previously set callback, or NULL if none.
 */
KSHangEventCallback kshang_setHangEventCallback(KSHangEventCallback callback);

/** Invokes the process-wide hang event callback, if one is set. Called by the
 * hang monitor on its own thread.
 */
void kshang_fireHangEvent(KSHangChangeType change, uint64_t startTimestamp, uint64_t endTimestamp);

#ifdef __cplusplus
}
#endif

#endif  // KSHangEvent_h
