//
//  KSCrashMonitor.c
//
//  Created by Karl Stenerud on 2012-02-12.
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

#include "KSCrashMonitor.h"

#include <memory.h>
#include <stdatomic.h>
#include <stdlib.h>
#include <unistd.h>

#include "KSCrashMonitorContext.h"
#include "KSCrashMonitorHelper.h"
#include "KSCrashMonitorRegistry.h"
#include "KSDebug.h"
#include "KSID.h"
#include "KSString.h"
#include "KSSystemCapabilities.h"
#include "KSThread.h"

// #define KSLogger_LocalLevel TRACE
#include "KSLogger.h"

// ============================================================================
#pragma mark - Globals -
// ============================================================================

static const size_t asyncSafeIndexMask = 1;
static const size_t asyncSafeItemCount = asyncSafeIndexMask + 1;
static const int maxSimultaneousExceptions = 200;  // 99.99999% sure we'll never exceed this.

static struct {
    KSCrashMonitorAPIList monitors;

    bool crashedDuringExceptionHandling;
    bool isHandlingFatalException;

    KSCrash_MonitorContext asyncSafeContext[asyncSafeItemCount];
    atomic_int asyncSafeContextIndex;

    /**
     * Special context to use when we need to bail out and ignore the exception.
     * bailoutContext.requirements.exitImmediately MUST always be true.
     */
    KSCrash_MonitorContext exitImmediatelyContext;

    thread_t threadsHandlingExceptions[maxSimultaneousExceptions];
    atomic_int handlingExceptionIndex;

    void (*onExceptionEvent)(struct KSCrash_MonitorContext *monitorContext);
} g_state;

static atomic_bool g_initialized;

// ============================================================================
#pragma mark - Internal -
// ============================================================================

static KSCrash_MonitorContext *asyncSafeContextAtIndex(int index)
{
    return &g_state.asyncSafeContext[((size_t)index) & asyncSafeIndexMask];
}

static void init(void)
{
    bool expectInitialized = false;
    if (!atomic_compare_exchange_strong(&g_initialized, &expectInitialized, true)) {
        return;
    }

    memset(&g_state, 0, sizeof(g_state));
    for (size_t i = 0; i < asyncSafeItemCount; i++) {
        ksid_generate(g_state.asyncSafeContext[i].eventID);
    }
    g_state.exitImmediatelyContext.requirements.shouldExitImmediately = true;
}

static bool isThreadAlreadyHandlingAnException(int maxCount, thread_t offendingThread, thread_t handlingThread)
{
    if (maxCount > maxSimultaneousExceptions) {
        maxCount = maxSimultaneousExceptions;
    }
    for (int i = 0; i < maxCount; i++) {
        thread_t handlerThread = g_state.threadsHandlingExceptions[i];
        if (handlerThread == handlingThread || handlerThread == offendingThread) {
            return true;
        }
    }
    return false;
}

static int beginHandlingException(thread_t handlerThread)
{
    int thisThreadHandlerIndex = g_state.handlingExceptionIndex++;
    if (thisThreadHandlerIndex < maxSimultaneousExceptions) {
        g_state.threadsHandlingExceptions[thisThreadHandlerIndex] = handlerThread;
    }
    return thisThreadHandlerIndex;
}

static void endHandlingException(int threadIndex)
{
    g_state.threadsHandlingExceptions[threadIndex] = 0;

    int expectedIndex = g_state.handlingExceptionIndex;
    if (expectedIndex == 0) {
        return;
    }

    // If the list has become empty (all simultaneously running
    // handlers have finished), reset the index back to 0.
    for (int i = 0; i < maxSimultaneousExceptions; i++) {
        if (g_state.threadsHandlingExceptions[i] != 0) {
            return;
        }
    }
    // If another thread got added while we were checking, this exchange will fail by
    // design. This is fine because all added threads will eventually perform this
    // same operation, and one of them will succeed.
    atomic_compare_exchange_strong(&g_state.handlingExceptionIndex, &expectedIndex, 0);
}

static KSCrash_MonitorContext *getNextMonitorContext(KSCrash_ExceptionHandlingRequirements requirements)
{
    KSCrash_MonitorContext *ctx = NULL;

    if (kscexc_requiresAsyncSafety(requirements)) {
        // Only fatal exception handlers can be initiated in an environment requiring async
        // safety, so only they will call `notify()` with `asyncSafety = true`.
        //
        // Therefore, only at most two such contexts can ever be simultaneously active
        // (crash and recrash), and they'll never be re-used because the app terminates
        // afterwards.
        //
        // If a third same-thread exception occurs, `notifyException()` calls `_exit(1)`.
        ctx = asyncSafeContextAtIndex(g_state.asyncSafeContextIndex++);
    } else {
        // If we're not in an environment requiring async safety, allocate a context on
        // the heap, and then free it in handleException().
        ctx = (KSCrash_MonitorContext *)calloc(1, sizeof(*ctx));
        ksid_generate(ctx->eventID);
        ctx->isHeapAllocated = true;
    }

    return ctx;
}

// ============================================================================
#pragma mark - API -
// ============================================================================

void kscm_setEventCallback(void (*onEvent)(struct KSCrash_MonitorContext *monitorContext))
{
    init();
    g_state.onExceptionEvent = onEvent;
}

bool kscm_activateMonitors(void)
{
    init();
    return kscmr_activateMonitors(&g_state.monitors);
}

void kscm_disableAllMonitors(void)
{
    init();
    kscmr_disableAllMonitors(&g_state.monitors);
}

static KSCrash_MonitorContext *notifyException(const mach_port_t offendingThread,
                                               const KSCrash_ExceptionHandlingRequirements initialRequirements)
{
    // This is the main decision point for all exception handling.
    //
    // If another exception occurs while we are already handling an exception, we need to decide what
    // to do based on whether the exception is fatal, what kinds of other exceptions are already in
    // progress, and whether there's already a handler running on this thread (i.e. our handler has crashed).
    //
    // | 1st exc   | 2nd exc | 3rd exc | same handler thread? | Procedure        |
    // | --------- | ------- | ------- | -------------------- | ---------------- |
    // | any       |         |         |                      | normal handling  |
    // | non-fatal | any     |         | N                    | normal handling  |
    // | fatal     | any     |         | N                    | block            |
    // | any       | any     |         | Y                    | recrash handling |
    // | any       | any     | any     | Y                    | exit             |
    //
    // Where:
    // - Normal handling means build a standard crash report.
    // - Recrash handling means build a minimal recrash report and be very cautious.
    // - Block means block this thread for a few seconds so it doesn't return before the other handler does.
    // - Exit means `_exit(1)` immediately because we can't recover anymore.
    //
    // If no other exceptions are in progress (simple case), handle things normally.
    // If a non-fatal exception is already in progress, they won't conflict so handle things normally.
    // If a fatal exception is already in progress, block to let the fatal exception handler finish.
    // If we get another exception on the SAME thread, we're dealing with a recrash.
    // If we get YET ANOTHER exception on the same thread (the recrash handler has crashed),
    // we're stuck in a crash loop, so exit the app.

    // Note: This function needs to be quick to minimize the chances
    //       of a context switch before we (possibly) suspend threads.

    const thread_t thisThread = (thread_t)ksthread_self();
    const int thisThreadHandlerIndex = beginHandlingException(thisThread);

    // Our state from before this exception
    const bool wasHandlingFatalException = g_state.isHandlingFatalException;
    const bool wasCrashedDuringExceptionHandling = g_state.crashedDuringExceptionHandling;

    // Our state now
    KSCrash_ExceptionHandlingRequirements requirements = initialRequirements;
    const bool isCrashedDuringExceptionHandling =
        isThreadAlreadyHandlingAnException(thisThreadHandlerIndex, offendingThread, thisThread);

    if (thisThreadHandlerIndex > maxSimultaneousExceptions) {
        // This should never happen, but it is theoretically possible for tons of
        // threads to cause exceptions at the exact same time, flooding our handler.
        // Drop the exception and disable future crash handling to give at least some
        // of the in-progress exceptions a chance to be reported.
        kscm_disableAllMonitors();
        return &g_state.exitImmediatelyContext;
    }

    if (isCrashedDuringExceptionHandling && wasCrashedDuringExceptionHandling) {
        // Something went VERY wrong. We're stuck in a crash loop. Shut down immediately.
        // Note: We don't abort() here because that would trigger yet another exception!
        _exit(1);
    }

    if (isCrashedDuringExceptionHandling) {
        // This is a recrash, so be more conservative in our handling.
        requirements.crashedDuringExceptionHandling = true;
        requirements.asyncSafety = true;
        requirements.shouldRecordAllThreads = false;
        requirements.isFatal = true;
    } else if (wasHandlingFatalException) {
        // This is an incidental exception that happened while we were handling a fatal
        // exception. Pause this handler to allow the other handler to finish.
        // 2 seconds should be ample time for it to finish and terminate the app.
        sleep(2);
    }

    g_state.crashedDuringExceptionHandling |= isCrashedDuringExceptionHandling;
    g_state.isHandlingFatalException |= requirements.isFatal;

    KSCrash_MonitorContext *ctx = getNextMonitorContext(requirements);
    ctx->threadHandlerIndex = thisThreadHandlerIndex;
    ctx->requirements = requirements;

    if (ctx->requirements.shouldRecordAllThreads) {
        KSLOG_DEBUG("shouldRecordAllThreads, so suspending threads");
        ctx->suspendedThreads = NULL;
        ctx->suspendedThreadsCount = 0;
        ksmc_suspendEnvironment(&ctx->suspendedThreads, &ctx->suspendedThreadsCount);
        if (ctx->suspendedThreadsCount > 0) {
            ctx->requirements.asyncSafetyBecauseThreadsSuspended = true;
        }
    }

    return ctx;
}

static void handleException(struct KSCrash_MonitorContext *ctx)
{
    if (ctx == NULL) {
        // This should never happen.
        KSLOG_ERROR("ctx is NULL");
        return;
    }

    // Allow all monitors a chance to add contextual info to the event.
    // The monitors will decide what they can do based on ctx->requirements.
    kscmr_addContextualInfoToEvent(&g_state.monitors, ctx);

    // Call the exception event handler if it exists
    if (g_state.onExceptionEvent) {
        g_state.onExceptionEvent(ctx);
    }

    // If the exception is fatal, we need to uninstall ourselves so that
    // other installed crash handler libraries can run when we finish.
    if (ctx->requirements.isFatal) {
        KSLOG_DEBUG("Exception is fatal. Restoring original handlers.");
        kscm_disableAllMonitors();
    }

    // Make sure we've resumed by this point.
    ksmc_resumeEnvironment(&ctx->suspendedThreads, &ctx->suspendedThreadsCount);

    endHandlingException(ctx->threadHandlerIndex);

    if (ctx->isHeapAllocated) {
        free(ctx);
    }
}

bool kscm_addMonitor(const KSCrashMonitorAPI *api)
{
    static KSCrash_ExceptionHandlerCallbacks exceptionCallbacks = {
        .notify = notifyException,
        .handle = handleException,
    };

    init();
    if (kscmr_addMonitor(&g_state.monitors, api)) {
        api->init(&exceptionCallbacks);
        return true;
    }
    return false;
}

void kscm_removeMonitor(const KSCrashMonitorAPI *api)
{
    init();
    kscmr_removeMonitor(&g_state.monitors, api);
}

// ============================================================================
#pragma mark - Testing API -
// ============================================================================

__attribute__((unused)) // For tests. Declared as extern in TestCase
void kscm_testcode_resetState(void)
{
    g_initialized = false;
    memset(&g_state, 0, sizeof(g_state));
}
