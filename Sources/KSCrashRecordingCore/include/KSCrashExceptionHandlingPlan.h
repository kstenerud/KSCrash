//
//  KSCrashExceptionHandlingPlan.h
//
//  Created by Karl Stenerud on 2025-08-24.
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

#ifndef HDR_KSCrashExceptionHandlingPlan_h
#define HDR_KSCrashExceptionHandlingPlan_h

#include <CoreFoundation/CoreFoundation.h>

#ifdef __cplusplus
extern "C" {
#endif

/**
 * Plan information that affects how a crash will be handled.
 *
 * Some fields can be modified by the user, while others are const (informational only).
 */
typedef struct {
    /**
     * The handler will try to record all threads if possible.
     *
     * Note: Recording all threads will require stopping them, which will trigger `requiresAsyncSafety`
     */
    bool shouldRecordAllThreads;

    /** If true, the handler will write a report about this event. */
    bool shouldWriteReport;

    /**
     * The process will terminate once exception handling completes.
     */
    const bool isFatal;

    /**
     * Only async-safe (aka signal-safe) functions may be called.
     *
     * This means that you cannot call anything that acquires locks or allocates
     * memory, which includes:
     * - Most of the C runtime library
     * - Most Swift and Objective-C code
     * - Any interpreted language frameworks such as React-Native
     * - Any transpiled code such as Kotlin or Unity
     * - Many C++ features, especially smart pointers
     *
     * Doing so risks causing a deadlock (which the user will experience as a
     * frozen app).
     *
     * @see https://www.man7.org/linux/man-pages/man7/signal-safety.7.html
     */
    const bool requiresAsyncSafety;

    /**
     * This crash happened as a result of handling another exception, so be
     * VERY conservative in what you do. Record just enough information to
     * diagnose a problem within the library or callback itself, and nothing more.
     *
     * Most commonly, callbacks should do NOTHING when this flag is set.
     *
     * The report writer will produce only a minimal report (without threads,
     * so this will also set `shouldRecordThreads` to false). The original
     * report and "recrash" reports will then be merged.
     */
    const bool crashedDuringExceptionHandling;

} CF_SWIFT_NAME(ExceptionHandlingPlan) KSCrash_ExceptionHandlingPlan;

#ifdef __cplusplus
}
#endif

#endif  // HDR_KSCrashExceptionHandlingPlan_h
