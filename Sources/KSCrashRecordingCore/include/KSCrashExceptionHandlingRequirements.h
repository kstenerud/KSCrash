//
//  KSCrashExceptionHandlingRequirements.h
//
//  Created by Karl Stenerud on 2025-08-11.
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

#ifndef HDR_KSCrashExceptionHandlingRequirements_h
#define HDR_KSCrashExceptionHandlingRequirements_h

#include <CoreFoundation/CoreFoundation.h>

#ifdef __cplusplus
extern "C" {
#endif

/**
 * Information about the current requirements for handling a particular event.
 */
typedef struct {
    /**
     * The handler will try to record all threads if possible.
     *
     * This will require stopping all threads, and so `asyncSafetyBecauseThreadsSuspended` will be set once the threads
     * are stopped.
     */
    unsigned shouldRecordAllThreads : 1;

    /**
     * The handler should try to write a report about this event.
     */
    unsigned shouldWriteReport : 1;

    /**
     * The process will terminate once exception handling completes.
     */
    unsigned isFatal : 1;

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
     * Note: Do not test this value directly! Use `kscexc_requiresAsyncSafety`.
     *
     * @see https://www.man7.org/linux/man-pages/man7/signal-safety.7.html
     */
    unsigned asyncSafety : 1;

    /**
     * Requires async safety, but only because all threads are currently suspended.
     * Once all threads are resumed, this field will be cleared.
     *
     * Note: Do not test this value directly! Use `kscexc_requiresAsyncSafety`.
     */
    unsigned asyncSafetyBecauseThreadsSuspended : 1;

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
    unsigned crashedDuringExceptionHandling : 1;

    /**
     * Something has gone very, VERY wrong, and as a result the library
     * cannot handle the exception.
     *
     * This is a very rare occurrence, but can happen if too many things cause
     * fatal exceptions simultaneously.
     *
     * Do nothing. Touch nothing. Exit the exception handler immediately.
     */
    unsigned shouldExitImmediately : 1;

} KSCrash_ExceptionHandlingRequirements;

static inline bool kscexc_requiresAsyncSafety(KSCrash_ExceptionHandlingRequirements requirements)
{
    return requirements.asyncSafety || requirements.asyncSafetyBecauseThreadsSuspended;
}

#ifdef __cplusplus
}
#endif

#endif  // HDR_KSCrashExceptionHandlingRequirements_h
