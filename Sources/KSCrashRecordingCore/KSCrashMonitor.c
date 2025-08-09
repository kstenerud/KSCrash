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
#include "KSDebug.h"
#include "KSID.h"
#include "KSString.h"
#include "KSSystemCapabilities.h"
#include "KSThread.h"

// #define KSLogger_LocalLevel TRACE
#include "KSLogger.h"

// ============================================================================
#pragma mark - Types -
// ============================================================================

/*
 Monitor list lockless algorithm:

 We choose an array of 100 entries because there will never be that many monitors in existence. No further allocations
 are made.
 - To iterate: Traverse the entire array, ignoring any null pointers.
 - To add an entry:
   - Search the array for a hole (null pointer)
   - Try to atomically swap in the monitor API pointer.
   - If the swap fails, continue searching for the next hole and repeat.
   - Once a swap is successful, iterate again, removing duplicates in case someone else also added the same API.
 - To remove an entry: Search for the pointer in the array and swap it for null.
*/
static const size_t monitorAPICount = 100;
typedef struct {
    _Atomic(const KSCrashMonitorAPI *) apis[monitorAPICount];
} MonitorList;

// ============================================================================
#pragma mark - Globals -
// ============================================================================

static const size_t asyncSafeIndexMask = 1;
static const size_t asyncSafeItemCount = asyncSafeIndexMask + 1;
static const int maxSimultaneousExceptions = 200;  // 99.99999% sure we'll never exceed this.

static struct {
    MonitorList monitors;

    bool crashedDuringExceptionHandling;
    bool isHandlingFatalException;

    KSCrash_MonitorContext asyncSafeContext[asyncSafeItemCount];
    atomic_int asyncSafeContextIndex;

    /**
     * Special context to use when we need to bail out and ignore the exception.
     * bailoutContext.currentPolicy.exitImmediately MUST always be true.
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

static bool addMonitor(MonitorList *list, const KSCrashMonitorAPI *api)
{
    bool added = false;
    for (size_t i = 0; i < monitorAPICount; i++) {
        if (atomic_load(list->apis + i) == api) {
            // This API has already been added by someone else.
            return false;
        }

        // Make sure we're swapping from null to our API, and not something else that got swapped in meanwhile.
        const KSCrashMonitorAPI *expectedAPI = NULL;
        if (atomic_compare_exchange_strong(list->apis + i, &expectedAPI, api)) {
            added = true;
            break;
        }
    }

    if (!added) {
        // This should never happen, but never say never!
        KSLOG_ERROR("Failed to add monitor API \"%s\"", api->monitorId());
        return false;
    }

    // Check for and remove duplicates in case another thread also just added the same API.
    bool found = false;
    for (size_t i = 0; i < monitorAPICount; i++) {
        if (atomic_load(list->apis + i) == api) {
            if (!found) {
                // Leave the first copy alone.
                found = true;
            } else {
                // Make sure we're swapping from our API to null, and not something else that got swapped in meanwhile.
                const KSCrashMonitorAPI *expectedAPI = api;
                atomic_compare_exchange_strong(list->apis + i, &expectedAPI, NULL);
            }
        }
    }
    return true;
}

static void removeMonitor(MonitorList *list, const KSCrashMonitorAPI *api)
{
    for (size_t i = 0; i < monitorAPICount; i++) {
        // Make sure we're swapping from our API to null, and not something else that got swapped in meanwhile.
        const KSCrashMonitorAPI *expectedAPI = api;
        if (atomic_compare_exchange_strong(list->apis + i, &expectedAPI, NULL)) {
            api->setEnabled(false);
        }
    }
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
    g_state.exitImmediatelyContext.currentPolicy.shouldExitImmediately = true;
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

static KSCrash_MonitorContext *getNextMonitorContext(KSCrash_ExceptionHandlingPolicy policy)
{
    KSCrash_MonitorContext *ctx = NULL;

    if (policy.requiresAsyncSafety) {
        // Only fatal exception handlers can be initiated in an environment requiring async
        // safety, so only they will call `notify()` with `requiresAsyncSafety = true`.
        //
        // Therefore, only at most two such contexts can ever be simultaneously active
        // (crash and recrash), and they'll never be re-used because the app terminates
        // afterwards.
        //
        // If a third same-thread exception occurs, `notifyException()` calls `exit(1)`.
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
    // Check for debugger and async safety
    bool isDebuggerUnsafe = ksdebug_isBeingTraced();

    if (isDebuggerUnsafe) {
        static bool hasWarned = false;
        if (!hasWarned) {
            hasWarned = true;
            KSLOGBASIC_WARN("    ************************ Crash Handler Notice ************************");
            KSLOGBASIC_WARN("    *     App is running in a debugger. Masking out unsafe monitors.     *");
            KSLOGBASIC_WARN("    * This means that most crashes WILL NOT BE RECORDED while debugging! *");
            KSLOGBASIC_WARN("    **********************************************************************");
        }
    }

    // Enable or disable monitors
    bool anyMonitorActive = false;
    for (size_t i = 0; i < monitorAPICount; i++) {
        const KSCrashMonitorAPI *api = g_state.monitors.apis[i];
        if (api == NULL) {
            // Found a hole. Skip it.
            continue;
        }
        KSCrashMonitorFlag flags = api->monitorFlags();
        bool shouldEnable = true;

        if (isDebuggerUnsafe && (flags & KSCrashMonitorFlagDebuggerUnsafe)) {
            shouldEnable = false;
        }

        api->setEnabled(shouldEnable);
        bool isEnabled = api->isEnabled();
        anyMonitorActive |= isEnabled;
        KSLOG_DEBUG("Monitor %s is now %sabled.", api->monitorId(), isEnabled ? "en" : "dis");
    }

    for (size_t i = 0; i < monitorAPICount; i++) {
        const KSCrashMonitorAPI *api = g_state.monitors.apis[i];
        if (api != NULL && api->isEnabled()) {
            api->notifyPostSystemEnable();
        }
    }

    return anyMonitorActive;
}

void kscm_disableAllMonitors(void)
{
    init();
    for (size_t i = 0; i < monitorAPICount; i++) {
        const KSCrashMonitorAPI *api = g_state.monitors.apis[i];
        if (api != NULL) {
            api->setEnabled(false);
        }
    }
    KSLOG_DEBUG("All monitors have been disabled.");
}

static KSCrash_MonitorContext *notifyException(const mach_port_t offendingThread,
                                               const KSCrash_ExceptionHandlingPolicy recommendations)
{
    // This is the main policy decision point for all exception handling.
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
    // - Exit means `exit(1)` immediately because we can't recover anymore.
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
    KSCrash_ExceptionHandlingPolicy policy = recommendations;
#if !KSCRASH_HAS_THREADS_API
    policy.shouldRecordThreads = false;
#endif
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
        exit(1);
    }

    if (isCrashedDuringExceptionHandling) {
        // This is a recrash, so be more conservative in our handling.
        policy.crashedDuringExceptionHandling = true;
        policy.requiresAsyncSafety = true;
        policy.shouldRecordThreads = false;
        policy.isFatal = true;
    } else if (wasHandlingFatalException) {
        // This is an incidental exception that happened while we were handling a fatal
        // exception. Pause this handler to allow the other handler to finish.
        // 2 seconds should be ample time for it to finish and terminate the app.
        sleep(2);
    }

    g_state.crashedDuringExceptionHandling |= isCrashedDuringExceptionHandling;
    g_state.isHandlingFatalException |= policy.isFatal;

    KSCrash_MonitorContext *ctx = getNextMonitorContext(policy);
    ctx->currentPolicy = policy;
    ctx->threadHandlerIndex = thisThreadHandlerIndex;

    if (ctx->currentPolicy.shouldRecordThreads) {
        // Once all threads are suspended, the environment requires async safety.
        ctx->currentPolicy.requiresAsyncSafety = true;
        ksmc_suspendEnvironment(&ctx->suspendedThreads, &ctx->suspendedThreadsCount);
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
    // The monitors will decide what they can do based on ctx->currentPolicy.
    for (size_t i = 0; i < monitorAPICount; i++) {
        const KSCrashMonitorAPI *api = g_state.monitors.apis[i];
        if (api != NULL && api->isEnabled()) {
            api->addContextualInfoToEvent(ctx);
        }
    }

    // Call the exception event handler if it exists
    if (g_state.onExceptionEvent) {
        g_state.onExceptionEvent(ctx);
    }

    // If the exception is fatal, we need to uninstall ourselves so that
    // other installed crash handler libraries can run when we finish.
    if (ctx->currentPolicy.isFatal) {
        KSLOG_DEBUG("Exception is fatal. Restoring original handlers.");
        kscm_disableAllMonitors();
    }

    if (ctx->currentPolicy.shouldRecordThreads) {
        ksmc_resumeEnvironment(ctx->suspendedThreads, ctx->suspendedThreadsCount);
    }

    endHandlingException(ctx->threadHandlerIndex);

    if (ctx->isHeapAllocated) {
        free(ctx);
    }
}

bool kscm_addMonitor(const KSCrashMonitorAPI *api)
{
    if (api == NULL) {
        return false;
    }

    static KSCrash_ExceptionHandlerCallbacks exceptionCallbacks = {
        .notify = notifyException,
        .handle = handleException,
    };

    init();

    if (addMonitor(&g_state.monitors, api)) {
        api->init(&exceptionCallbacks);
        KSLOG_DEBUG("Monitor %s injected.", api->monitorId());
        return true;
    } else {
        KSLOG_DEBUG("Monitor %s already exists. Skipping addition.", api->monitorId());
        return false;
    }
}

void kscm_removeMonitor(const KSCrashMonitorAPI *api)
{
    if (api == NULL) {
        return;
    }

    init();
    removeMonitor(&g_state.monitors, api);
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
