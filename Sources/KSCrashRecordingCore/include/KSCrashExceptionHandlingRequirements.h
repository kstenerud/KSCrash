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
 *
 * This struct travels in both directions and the two kinds of field sit side by side, so
 * every field says which it is:
 *
 * - `Input` is declared by the caller and passed to notify.
 * - `Output` is set by the handler and read back off the context notify returns. A caller
 *   never sets one.
 * - An input marked "the handler may overrule it" can come back changed, because an event
 *   raised while our own handler is crashing is no longer the event the caller described.
 *   Read those back off the returned context rather than assuming what you passed survived.
 */
typedef struct {
    /**
     * The handler will try to record all threads if possible.
     *
     * This will require stopping all threads, and so `asyncSafetyBecauseThreadsSuspended` will be set once the threads
     * are stopped.
     *
     * Input. The handler may overrule it.
     */
    unsigned shouldRecordAllThreads : 1;

    /**
     * The handler should try to write a report about this event.
     *
     * Input.
     */
    unsigned shouldWriteReport : 1;

    /**
     * The subject of this event will terminate once exception handling completes.
     *
     * The subject is this process unless `isRemoteSubject` is set. To ask whether THIS
     * process is dying, which is what every "wind down now" decision means, use
     * `kscexc_isLocallyFatal` rather than this field alone.
     *
     * Input. The handler may overrule it.
     */
    unsigned isFatal : 1;

    /**
     * The exit was expected and not a crash (e.g., SIGTERM).
     * Only meaningful when `isFatal` is true.
     *
     * Input. The handler may overrule it.
     */
    unsigned isCleanExit : 1;

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
     *
     * Input. The handler may overrule it.
     */
    unsigned asyncSafety : 1;

    /**
     * Requires async safety, but only because all threads are currently suspended.
     * Once all threads are resumed, this field will be cleared.
     *
     * Note: Do not test this value directly! Use `kscexc_requiresAsyncSafety`.
     *
     * Output, in answer to `shouldRecordAllThreads`.
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
     *
     * Output.
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
     *
     * Output.
     */
    unsigned shouldExitImmediately : 1;

    /**
     * The event describes a subject other than the current process (e.g. another process's
     * corpse, or a previous run of this app). The reporting process itself is healthy.
     *
     * When set, the machinery skips every process-local effect: no threads of this
     * process are suspended (`shouldRecordAllThreads` becomes purely a directive to
     * record all of the subject's threads, which are frozen in their own task), `isFatal`
     * describes the event rather than this process (no fatal handler state is latched,
     * monitors stay enabled, and the current run is not marked as crashed).
     *
     * Note: Do not test this value directly! Use `kscexc_isRemoteSubject`.
     *
     * Input. The handler may overrule it.
     */
    unsigned isRemoteSubject : 1;

    /**
     * Drop this event rather than write its report alongside one already being written.
     *
     * Reports are written one at a time where that costs nothing, because the handler
     * keeps a single record of which report it wrote last and recrash handling rewrites
     * that report in place.
     *
     * Set it only where losing the event costs nothing, because the handler drops it
     * outright and says so through `refusedReportInFlight`. Leave it clear otherwise:
     * such events are neither delayed nor refused, since nothing waits here. A report
     * write is far longer than any wait a crash path can afford, so waiting would buy
     * delay and no exclusion.
     *
     * Input. The handler may overrule it.
     */
    unsigned yieldsToReportInFlight : 1;

    /**
     * The handler refused this event because a report was already being written and the
     * event declared `yieldsToReportInFlight`. The returned context is a shared bail-out
     * slot: do nothing with it, and do not call the handler.
     *
     * Output, in answer to `yieldsToReportInFlight`.
     */
    unsigned refusedReportInFlight : 1;

} KSCrash_ExceptionHandlingRequirements CF_SWIFT_NAME(EventRequirements);

static inline bool kscexc_requiresAsyncSafety(KSCrash_ExceptionHandlingRequirements requirements)
{
    return requirements.asyncSafety || requirements.asyncSafetyBecauseThreadsSuspended;
}

/** True when the event describes a subject other than the current process (see `isRemoteSubject`).
 *  Process-local effects (thread suspension, fatal handler state, run-state bookkeeping such as
 *  the Lifecycle sidecar's cleanShutdown/fatalReported) must not fire for such an event.
 */
static inline bool kscexc_isRemoteSubject(KSCrash_ExceptionHandlingRequirements requirements)
{
    return requirements.isRemoteSubject;
}

/** True when the event is fatal FOR THIS PROCESS: a remote subject's death is fatal for the
 *  subject, not for the healthy reporter writing about it. Every consumer that latches fatal
 *  state, marks the run as crashed, or otherwise reacts to "this process is dying" must use
 *  this, not `isFatal` alone.
 */
static inline bool kscexc_isLocallyFatal(KSCrash_ExceptionHandlingRequirements requirements)
{
    return requirements.isFatal && !kscexc_isRemoteSubject(requirements);
}

#ifdef __cplusplus
}
#endif

#endif  // HDR_KSCrashExceptionHandlingRequirements_h
