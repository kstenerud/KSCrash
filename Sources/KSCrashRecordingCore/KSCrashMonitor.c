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
#include "KSCrashMonitorHelper.h"
#include "KSCrashMonitorContext.h"

#include "KSDebug.h"
#include "KSThread.h"
#include "KSSystemCapabilities.h"

#include <memory.h>
#include <stdlib.h>

//#define KSLogger_LocalLevel TRACE
#include "KSLogger.h"

typedef KSCrashMonitorAPI* (*GetMonitorAPIFunc)(void);

typedef struct
{
    GetMonitorAPIFunc* functions; // Array of MonitorAPIs
    size_t count;
    size_t capacity;
} MonitorList;

// ============================================================================
#pragma mark - Globals -
// ============================================================================

static MonitorList g_monitors;

static bool g_handlingFatalException = false;
static bool g_crashedDuringExceptionHandling = false;
static bool g_requiresAsyncSafety = false;

static void (*g_onExceptionEvent)(struct KSCrash_MonitorContext* monitorContext);

#define INITIAL_MONITOR_CAPACITY 10

static void initializeMonitorFuncList(MonitorList* list)
{
    list->count = 0;
    list->capacity = INITIAL_MONITOR_CAPACITY;
    list->functions = (GetMonitorAPIFunc*)malloc(list->capacity * sizeof(GetMonitorAPIFunc));
}

static void addMonitorFunc(MonitorList* list, GetMonitorAPIFunc func)
{
    if (list->count >= list->capacity)
    {
        list->capacity *= 2;
        list->functions = (GetMonitorAPIFunc*)realloc(list->functions, list->capacity * sizeof(GetMonitorAPIFunc));
    }
    list->functions[list->count++] = func;
}

static void freeMonitorFuncList(MonitorList* list)
{
    free(list->functions);
    list->functions = NULL;
    list->count = 0;
    list->capacity = 0;
}

#pragma mark - Helpers

static inline const char* getMonitorNameForLogging(KSCrashMonitorAPI* api)
{
    return kscm_getMonitorName(api) ?: "Unknown";
}

// ============================================================================
#pragma mark - API -
// ============================================================================

void kscm_activateMonitors()
{
    // Check for debugger and async safety
    bool isDebuggerUnsafe = ksdebug_isBeingTraced();
    bool isAsyncSafeRequired = g_requiresAsyncSafety;

    if (isDebuggerUnsafe)
    {
        static bool hasWarned = false;
        if (!hasWarned)
        {
            hasWarned = true;
            KSLOGBASIC_WARN("    ************************ Crash Handler Notice ************************");
            KSLOGBASIC_WARN("    *     App is running in a debugger. Masking out unsafe monitors.     *");
            KSLOGBASIC_WARN("    * This means that most crashes WILL NOT BE RECORDED while debugging! *");
            KSLOGBASIC_WARN("    **********************************************************************");
        }
    }

    if (isAsyncSafeRequired)
    {
        KSLOG_DEBUG("Async-safe environment detected. Masking out unsafe monitors.");
    }

    // Enable or disable monitors
    for (size_t i = 0; i < g_monitors.count; i++)
    {
        KSCrashMonitorAPI* api = g_monitors.functions[i]();
        KSCrashMonitorProperty properties = kscm_getMonitorProperties(api);
        bool shouldEnable = true;

        if (isDebuggerUnsafe && (properties & KSCrashMonitorPropertyDebuggerUnsafe))
        {
            shouldEnable = false;
        }

        if (isAsyncSafeRequired && !(properties & KSCrashMonitorPropertyAsyncSafe))
        {
            shouldEnable = false;
        }

        kscm_setMonitorEnabled(api, shouldEnable);
    }

    // Log active monitors
    KSLOG_DEBUG("Active monitors are now:");
    for (size_t i = 0; i < g_monitors.count; i++)
    {
        KSCrashMonitorAPI* api = g_monitors.functions[i]();
        if (kscm_isMonitorEnabled(api))
        {
            KSLOG_DEBUG("Monitor %s is enabled.", getMonitorNameForLogging(api));
        }
        else
        {
            KSLOG_DEBUG("Monitor %s is disabled.", getMonitorNameForLogging(api));
        }
    }

    // Notify monitors about system enable
    for (size_t i = 0; i < g_monitors.count; i++)
    {
        KSCrashMonitorAPI* api = g_monitors.functions[i]();
        kscm_notifyPostSystemEnable(api);
    }
}

void kscm_disableAllMonitors()
{
    for (size_t i = 0; i < g_monitors.count; i++)
    {
        KSCrashMonitorAPI* api = g_monitors.functions[i]();
        kscm_setMonitorEnabled(api, false);
    }
    KSLOG_DEBUG("All monitors have been disabled.");
}

void kscm_addMonitor(KSCrashMonitorAPI* api)
{
    addMonitorFunc(&g_monitors, (GetMonitorAPIFunc)api);
    KSLOG_DEBUG("Monitor %s injected.", getMonitorNameForLogging(api));
}

//KSCrashMonitorType kscm_getActiveMonitors(void)
//{
//    return g_monitors;
//}


// ============================================================================
#pragma mark - Private API -
// ============================================================================

bool kscm_notifyFatalExceptionCaptured(bool isAsyncSafeEnvironment)
{
    g_requiresAsyncSafety |= isAsyncSafeEnvironment; // Don't let it be unset.
    if(g_handlingFatalException)
    {
        g_crashedDuringExceptionHandling = true;
    }
    g_handlingFatalException = true;
    if(g_crashedDuringExceptionHandling)
    {
        KSLOG_INFO("Detected crash in the crash reporter. Uninstalling KSCrash.");
        kscm_disableAllMonitors();
    }
    return g_crashedDuringExceptionHandling;
}

void kscm_handleException(struct KSCrash_MonitorContext* context)
{
    // We're handling a crash if the crash type is fatal
    bool hasFatalProperty = (context->monitorProperties & KSCrashMonitorPropertyFatal) != KSCrashMonitorPropertyNone;
    context->handlingCrash = context->handlingCrash || hasFatalProperty;

    context->requiresAsyncSafety = g_requiresAsyncSafety;
    if (g_crashedDuringExceptionHandling)
    {
        context->crashedDuringCrashHandling = true;
    }

    // Add contextual info to the event for all enabled monitors
    for (size_t i = 0; i < g_monitors.count; i++)
    {
        KSCrashMonitorAPI* api = g_monitors.functions[i]();
        if (kscm_isMonitorEnabled(api))
        {
            kscm_addContextualInfoToEvent(api, context);
        }
    }

    // Call the exception event handler if it exists
    if (g_onExceptionEvent)
    {
        g_onExceptionEvent(context);
    }

    // Restore original handlers if the exception is fatal and not already handled
    if (context->currentSnapshotUserReported)
    {
        g_handlingFatalException = false;
    }
    else
    {
        if (g_handlingFatalException && !g_crashedDuringExceptionHandling)
        {
            KSLOG_DEBUG("Exception is fatal. Restoring original handlers.");
            kscm_disableAllMonitors();
        }
    }

    // Done handling the crash
    context->handlingCrash = false;
}
