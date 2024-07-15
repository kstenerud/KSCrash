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
#include <stdlib.h>

#include "KSCrashMonitorContext.h"
#include "KSCrashMonitorHelper.h"
#include "KSDebug.h"
#include "KSString.h"
#include "KSSystemCapabilities.h"
#include "KSThread.h"

// #define KSLogger_LocalLevel TRACE
#include "KSLogger.h"

typedef struct {
    KSCrashMonitorAPI **apis;  // Array of MonitorAPIs
    size_t count;
    size_t capacity;
} MonitorList;

#define INITIAL_MONITOR_CAPACITY 15

// ============================================================================
#pragma mark - Globals -
// ============================================================================

static MonitorList g_monitors = {};

static bool g_areMonitorsInitialized = false;
static bool g_handlingFatalException = false;
static bool g_crashedDuringExceptionHandling = false;
static bool g_requiresAsyncSafety = false;

static void (*g_onExceptionEvent)(struct KSCrash_MonitorContext *monitorContext);

static void initializeMonitorList(MonitorList *list)
{
    list->count = 0;
    list->capacity = INITIAL_MONITOR_CAPACITY;
    list->apis = (KSCrashMonitorAPI **)malloc(list->capacity * sizeof(KSCrashMonitorAPI *));
}

static void addMonitor(MonitorList *list, KSCrashMonitorAPI *api)
{
    if (list->count >= list->capacity) {
        list->capacity *= 2;
        list->apis = (KSCrashMonitorAPI **)realloc(list->apis, list->capacity * sizeof(KSCrashMonitorAPI *));
    }
    list->apis[list->count++] = api;
}

static void removeMonitor(MonitorList *list, const KSCrashMonitorAPI *api)
{
    if (list == NULL || api == NULL) {
        KSLOG_DEBUG("Either list or func is NULL. Removal operation aborted.");
        return;
    }

    bool found = false;

    for (size_t i = 0; i < list->count; i++) {
        if (list->apis[i] == api) {
            found = true;

            kscm_setMonitorEnabled(list->apis[i], false);

            // Replace the current monitor with the last monitor in the list
            list->apis[i] = list->apis[list->count - 1];
            list->count--;
            list->apis[list->count] = NULL;

            KSLOG_DEBUG("Monitor %s removed from the list.", getMonitorNameForLogging(func));
            break;
        }
    }

    if (!found) {
        KSLOG_DEBUG("Monitor %s not found in the list. No removal performed.", getMonitorNameForLogging(func));
    }
}

static void freeMonitorFuncList(MonitorList *list)
{
    free(list->apis);
    list->apis = NULL;
    list->count = 0;
    list->capacity = 0;

    g_areMonitorsInitialized = false;
}

__attribute__((unused)) // For tests. Declared as extern in TestCase
void kscm_resetState(void)
{
    freeMonitorFuncList(&g_monitors);
    g_handlingFatalException = false;
    g_crashedDuringExceptionHandling = false;
    g_requiresAsyncSafety = false;
    g_onExceptionEvent = NULL;
}

#pragma mark - Helpers

__attribute__((unused))  // Suppress unused function warnings, especially in release builds.
static inline const char *
getMonitorNameForLogging(const KSCrashMonitorAPI *api)
{
    return kscm_getMonitorId(api) ?: "Unknown";
}

// ============================================================================
#pragma mark - API -
// ============================================================================

void kscm_setEventCallback(void (*onEvent)(struct KSCrash_MonitorContext *monitorContext))
{
    g_onExceptionEvent = onEvent;
}

bool kscm_activateMonitors(void)
{
    // Check for debugger and async safety
    bool isDebuggerUnsafe = ksdebug_isBeingTraced();
    bool isAsyncSafeRequired = g_requiresAsyncSafety;

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
    for (size_t i = 0; i < g_monitors.count; i++) {
        KSCrashMonitorAPI *api = g_monitors.apis[i];
        KSCrashMonitorFlag flags = kscm_getMonitorFlags(api);
        bool shouldEnable = true;

        if (isDebuggerUnsafe && (flags & KSCrashMonitorFlagDebuggerUnsafe)) {
            shouldEnable = false;
        }

        if (isAsyncSafeRequired && !(flags & KSCrashMonitorFlagAsyncSafe)) {
            shouldEnable = false;
        }

        kscm_setMonitorEnabled(api, shouldEnable);
    }

    bool anyMonitorActive = false;

    // Log active monitors
    KSLOG_DEBUG("Active monitors are now:");
    for (size_t i = 0; i < g_monitors.count; i++) {
        KSCrashMonitorAPI *api = g_monitors.apis[i];
        if (kscm_isMonitorEnabled(api)) {
            KSLOG_DEBUG("Monitor %s is enabled.", getMonitorNameForLogging(api));
            anyMonitorActive = true;
        } else {
            KSLOG_DEBUG("Monitor %s is disabled.", getMonitorNameForLogging(api));
        }
    }

    // Notify monitors about system enable
    for (size_t i = 0; i < g_monitors.count; i++) {
        KSCrashMonitorAPI *api = g_monitors.apis[i];
        kscm_notifyPostSystemEnable(api);
    }

    return anyMonitorActive;
}

void kscm_disableAllMonitors(void)
{
    for (size_t i = 0; i < g_monitors.count; i++) {
        KSCrashMonitorAPI *api = g_monitors.apis[i];
        kscm_setMonitorEnabled(api, false);
    }
    KSLOG_DEBUG("All monitors have been disabled.");
}

bool kscm_addMonitor(KSCrashMonitorAPI *api)
{
    if (api == NULL) {
        KSLOG_DEBUG("Attempted to add a NULL monitor. Operation aborted.");
        return false;
    }

    const char *newMonitorId = kscm_getMonitorId(api);
    if (newMonitorId == NULL) {
        KSLOG_DEBUG("Monitor has a NULL ID. Operation aborted.");
        return false;
    }

    if (!g_areMonitorsInitialized) {
        initializeMonitorList(&g_monitors);
        g_areMonitorsInitialized = true;
    }

    // Check for duplicate monitors
    for (size_t i = 0; i < g_monitors.count; i++) {
        KSCrashMonitorAPI *existingApi = g_monitors.apis[i];
        const char *existingMonitorId = kscm_getMonitorId(existingApi);

        if (ksstring_safeStrcmp(existingMonitorId, newMonitorId) == 0) {
            KSLOG_DEBUG("Monitor %s already exists. Skipping addition.", getMonitorNameForLogging(api));
            return false;
        }
    }

    addMonitor(&g_monitors, api);
    KSLOG_DEBUG("Monitor %s injected.", getMonitorNameForLogging(api));
    return true;
}

void kscm_removeMonitor(const KSCrashMonitorAPI *api)
{
    if (api == NULL) {
        KSLOG_DEBUG("Attempted to remove a NULL monitor. Operation aborted.");
        return;
    }

    removeMonitor(&g_monitors, api);
}

// KSCrashMonitorType kscm_getActiveMonitors(void)
//{
//     return g_monitors;
// }

// ============================================================================
#pragma mark - Private API -
// ============================================================================

bool kscm_notifyFatalExceptionCaptured(bool isAsyncSafeEnvironment)
{
    g_requiresAsyncSafety |= isAsyncSafeEnvironment;  // Don't let it be unset.
    if (g_handlingFatalException) {
        g_crashedDuringExceptionHandling = true;
    }
    g_handlingFatalException = true;
    if (g_crashedDuringExceptionHandling) {
        KSLOG_INFO("Detected crash in the crash reporter. Uninstalling KSCrash.");
        kscm_disableAllMonitors();
    }
    return g_crashedDuringExceptionHandling;
}

void kscm_handleException(struct KSCrash_MonitorContext *context)
{
    // We're handling a crash if the crash type is fatal
    bool hasFatalFlag = (context->monitorFlags & KSCrashMonitorFlagFatal) != KSCrashMonitorFlagNone;
    context->handlingCrash = context->handlingCrash || hasFatalFlag;

    context->requiresAsyncSafety = g_requiresAsyncSafety;
    if (g_crashedDuringExceptionHandling) {
        context->crashedDuringCrashHandling = true;
    }

    // Add contextual info to the event for all enabled monitors
    for (size_t i = 0; i < g_monitors.count; i++) {
        KSCrashMonitorAPI *api = g_monitors.apis[i];
        if (kscm_isMonitorEnabled(api)) {
            kscm_addContextualInfoToEvent(api, context);
        }
    }

    // Call the exception event handler if it exists
    if (g_onExceptionEvent) {
        g_onExceptionEvent(context);
    }

    // Restore original handlers if the exception is fatal and not already handled
    if (context->currentSnapshotUserReported) {
        g_handlingFatalException = false;
    } else {
        if (g_handlingFatalException && !g_crashedDuringExceptionHandling) {
            KSLOG_DEBUG("Exception is fatal. Restoring original handlers.");
            kscm_disableAllMonitors();
        }
    }

    // Done handling the crash
    context->handlingCrash = false;
}
