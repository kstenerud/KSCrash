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
 - To iterate: Traverse the entire array, ignoring any null ponters.
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

static const size_t eventIdCount = 2;
static struct {
    MonitorList monitors;

    bool crashedDuringExceptionHandling;
    KSCrash_ExceptionHandlingPolicy currentPolicy;

    char eventIds[eventIdCount][40];
    size_t eventIdIdx;

    void (*onExceptionEvent)(struct KSCrash_MonitorContext *monitorContext);
} g_state;

static atomic_bool g_initialized;

// ============================================================================
#pragma mark - Internal -
// ============================================================================

static bool addMonitor(MonitorList *list, const KSCrashMonitorAPI *api)
{
    bool added = false;
    for (size_t i = 0; i < monitorAPICount; i++) {
        if (list->apis[i] == api) {
            return false;
        }

        if (list->apis[i] == NULL) {
            // Make sure we're swapping from null to our API, and not something else that got swapped in meanwhile.
            const KSCrashMonitorAPI *expectedAPI = NULL;
            if (atomic_compare_exchange_strong(list->apis + i, &expectedAPI, api)) {
                added = true;
                break;
            }
        }
    }

    if (!added) {
        // This should never happen, but never say never!
        KSLOG_ERROR("Failed to add monitor API \"%s\"", api->monitorId());
        return false;
    }

    // Check for and remove duplicates in case another thread just added the same API.
    bool found = false;
    for (size_t i = 0; i < monitorAPICount; i++) {
        if (list->apis[i] == api) {
            if (!found) {
                // Leave the first copy there.
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
        if (list->apis[i] == api) {
            // Make sure we're swapping from our API to null, and not something else that got swapped in meanwhile.
            const KSCrashMonitorAPI *expectedAPI = api;
            if (atomic_compare_exchange_strong(list->apis + i, &expectedAPI, NULL)) {
                api->setEnabled(false);
            }
        }
    }
}

static void regenerateEventIds(void)
{
    for (size_t i = 0; i < eventIdCount; i++) {
        ksid_generate(g_state.eventIds[i]);
    }
    g_state.eventIdIdx = 0;
}

static void init(void)
{
    bool expectInitialized = false;
    if (!atomic_compare_exchange_strong(&g_initialized, &expectInitialized, true)) {
        return;
    }

    memset(&g_state, 0, sizeof(g_state));
    regenerateEventIds();
}

__attribute__((unused)) // For tests. Declared as extern in TestCase
void kscm_resetState(void)
{
    g_initialized = false;
    memset(&g_state, 0, sizeof(g_state));
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
    bool isAsyncSafeRequired = g_state.currentPolicy.asyncSafety;

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

    if (isAsyncSafeRequired) {
        KSLOG_DEBUG("Async-safe environment detected. Masking out unsafe monitors.");
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

        if (isAsyncSafeRequired && !(flags & KSCrashMonitorFlagAsyncSafe)) {
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

static bool notifyException(KSCrash_ExceptionHandlingPolicy recommendations)
{
    g_state.currentPolicy.asyncSafety |= recommendations.asyncSafety;  // Don't let it be unset.
    if (!recommendations.isFatal) {
        return false;
    }

    if (g_state.currentPolicy.isFatal) {
        g_state.crashedDuringExceptionHandling = true;
    }
    g_state.currentPolicy.isFatal = true;
    if (g_state.crashedDuringExceptionHandling) {
        KSLOG_INFO("Detected crash in the crash reporter. Uninstalling KSCrash.");
        kscm_disableAllMonitors();
    }
    return g_state.crashedDuringExceptionHandling;
}

static void handleException(struct KSCrash_MonitorContext *context)
{
    context->handlingCrash |= g_state.currentPolicy.isFatal;

    context->requiresAsyncSafety = g_state.currentPolicy.asyncSafety;
    if (g_state.crashedDuringExceptionHandling) {
        context->crashedDuringCrashHandling = true;
    }

    if (!g_state.currentPolicy.asyncSafety) {
        // If we don't need async-safety (NSException, user exception), then this is safe to call.
        ksid_generate(context->eventID);
    } else {
        // Otherwise use the pre-built primary or secondary event ID. We won't ever use
        // more than two (crash, recrash) because the app will terminate afterwards.
        if (g_state.eventIdIdx >= eventIdCount) {
            // Very unlikely, but if this happens, we're stuck in a handler loop.
            KSLOG_ERROR(
                "Requesting a pre-built event ID, but we've already used both up! Aborting exception handling.");
            return;
        }
        memcpy(context->eventID, g_state.eventIds[g_state.eventIdIdx++], sizeof(context->eventID));
    }

    // Add contextual info to the event for all enabled monitors
    for (size_t i = 0; i < monitorAPICount; i++) {
        const KSCrashMonitorAPI *api = g_state.monitors.apis[i];
        if (api != NULL && api->isEnabled()) {
            api->addContextualInfoToEvent(context);
        }
    }

    // Call the exception event handler if it exists
    if (g_state.onExceptionEvent) {
        g_state.onExceptionEvent(context);
    }

    // Restore original handlers if the exception is fatal and not already handled
    if (g_state.currentPolicy.isFatal && !g_state.crashedDuringExceptionHandling) {
        KSLOG_DEBUG("Exception is fatal. Restoring original handlers.");
        kscm_disableAllMonitors();
    }

    // Done handling the crash
    context->handlingCrash = false;
}

bool kscm_addMonitor(const KSCrashMonitorAPI *api)
{
    static KSCrash_ExceptionHandlerCallbacks exceptionCallbacks = {
        .notify = notifyException,
        .handle = handleException,
    };

    init();

    if (addMonitor(&g_state.monitors, api)) {
        api->init(&exceptionCallbacks);
        KSLOG_DEBUG("Monitor %s injected.", getMonitorNameForLogging(api));
        return true;
    } else {
        KSLOG_DEBUG("Monitor %s already exists. Skipping addition.", getMonitorNameForLogging(api));
        return false;
    }
}

void kscm_removeMonitor(const KSCrashMonitorAPI *api)
{
    init();
    removeMonitor(&g_state.monitors, api);
}

// ============================================================================
#pragma mark - Private API -
// ============================================================================

void kscm_regenerateEventIDs(void) { regenerateEventIds(); }

void kscm_clearAsyncSafetyState(void) { g_state.currentPolicy.asyncSafety = false; }
