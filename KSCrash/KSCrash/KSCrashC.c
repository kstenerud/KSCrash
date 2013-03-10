//
//  KSCrashC.c
//
//  Created by Karl Stenerud on 2012-01-28.
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


#include "KSCrashC.h"

#include "KSCrashReport.h"
#include "KSMach.h"
#include "KSObjC.h"
#include "KSSignalInfo.h"
#include "KSSystemInfoC.h"
#include "KSZombie.h"
#include "KSCrashSentry_Deadlock.h"

//#define KSLogger_LocalLevel TRACE
#include "KSLogger.h"

#include <errno.h>
#include <fcntl.h>
#include <mach/mach_time.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>


// ============================================================================
#pragma mark - Globals -
// ============================================================================

/** Single, global crash context. */
static KSCrash_Context g_crashReportContext = {{0}};

/** Path to store the next crash report. */
static char* g_crashReportFilePath;

/** Path to store the next crash report (only if the crash manager crashes). */
static char* g_recrashReportFilePath;

/** Path to store the state file. */
static char* g_stateFilePath;


// ============================================================================
#pragma mark - Utility -
// ============================================================================

static inline KSCrash_Context* crashContext(void)
{
    return &g_crashReportContext;
}


// ============================================================================
#pragma mark - Callbacks -
// ============================================================================

// Avoiding static methods due to linker issue.

/** Called when a crash occurs.
 *
 * This function gets passed as a callback to a crash handler.
 */
void kscrash_i_onCrash(void)
{
    KSLOG_DEBUG("Updating application state to note crash.");
    kscrashstate_notifyAppCrash();

    KSCrash_Context* context = crashContext();

    if(context->config.printTraceToStdout)
    {
        kscrashreport_logCrash(context);
    }

    if(context->crash.crashedDuringCrashHandling)
    {
        kscrashreport_writeMinimalReport(context, g_recrashReportFilePath);
    }
    else
    {
        kscrashreport_writeStandardReport(context, g_crashReportFilePath);
    }
}


// ============================================================================
#pragma mark - API -
// ============================================================================

bool kscrash_install(const char* const crashReportFilePath,
                     const char* const recrashReportFilePath,
                     const char* const stateFilePath,
                     const char* const crashID)
{
    KSLOG_DEBUG("Installing crash reporter.");
    KSLOG_TRACE("reportFilePath = %s", crashReportFilePath);
    KSLOG_TRACE("secondaryReportFilePath = %s", recrashReportFilePath);
    KSLOG_TRACE("stateFilePath = %s", stateFilePath);
    KSLOG_TRACE("crashID = %s", crashID);

    static volatile sig_atomic_t initialized = 0;
    if(!initialized)
    {
        initialized = 1;

        g_stateFilePath = strdup(stateFilePath);
        g_crashReportFilePath = strdup(crashReportFilePath);
        g_recrashReportFilePath = strdup(recrashReportFilePath);
        KSCrash_Context* context = crashContext();
        context->crash.onCrash = kscrash_i_onCrash;

        if(ksmach_isBeingTraced())
        {
            KSLOGBASIC_WARN("KSCrash: App is running in a debugger."
                            " Crash sentries have been disabled for the sanity of all.");
        }
        else if(kscrashsentry_installWithContext(&context->crash,
                                                 KSCrashTypeAll) == 0)
        {
            KSLOG_ERROR("Failed to install any handlers");
        }

        if(!kscrashstate_init(g_stateFilePath, &context->state))
        {
            KSLOG_ERROR("Failed to initialize persistent crash state");
        }
        context->state.appLaunchTime = mach_absolute_time();
        context->config.systemInfoJSON = kssysteminfo_toJSON();
        context->config.processName = kssystemInfo_copyProcessName();
        context->config.crashID = strdup(crashID);

        KSLOG_DEBUG("Installation complete.");
        return true;
    }

    KSLOG_ERROR("Called more than once");
    return false;
}

void kscrash_setUserInfoJSON(const char* const userInfoJSON)
{
    KSLOG_TRACE("set userInfoJSON to %p", userInfoJSON);
    KSCrash_Context* context = crashContext();
    if(context->config.userInfoJSON != NULL)
    {
        KSLOG_TRACE("Free old data at %p", context->config.userInfoJSON);
        free((void*)context->config.userInfoJSON);
    }
    if(userInfoJSON != NULL)
    {
        context->config.userInfoJSON = strdup(userInfoJSON);
        KSLOG_TRACE("Duplicated string to %p", context->config.userInfoJSON);
    }
}

void kscrash_setZombieCacheSize(size_t zombieCacheSize)
{
    kszombie_uninstall();
    if(zombieCacheSize > 0)
    {
        kszombie_install(zombieCacheSize);
    }
}

void kscrash_setDeadlockWatchdogInterval(double deadlockWatchdogInterval)
{
    kscrashsentry_setDeadlockHandlerWatchdogInterval(deadlockWatchdogInterval);
}

void kscrash_setPrintTraceToStdout(bool printTraceToStdout)
{
    crashContext()->config.printTraceToStdout = printTraceToStdout;
}

void kscrash_setIntrospectMemory(bool introspectMemory)
{
    crashContext()->config.introspectionRules.enabled = introspectMemory;
}

void kscrash_setDoNotIntrospectClasses(const char** doNotIntrospectClasses, size_t length)
{
    const char** oldClasses = crashContext()->config.introspectionRules.restrictedClasses;
    size_t oldClassesLength = crashContext()->config.introspectionRules.restrictedClassesCount;
    const char** newClasses = nil;
    size_t newClassesLength = 0;
    
    if(doNotIntrospectClasses != nil && length > 0)
    {
        newClassesLength = length;
        newClasses = malloc(sizeof(*newClasses) * newClassesLength);
        if(newClasses == nil)
        {
            KSLOG_ERROR("Could not allocate memory");
            return;
        }
        
        for(size_t i = 0; i < newClassesLength; i++)
        {
            newClasses[i] = strdup(doNotIntrospectClasses[i]);
        }
    }

    crashContext()->config.introspectionRules.restrictedClasses = newClasses;
    crashContext()->config.introspectionRules.restrictedClassesCount = newClassesLength;

    if(oldClasses != nil)
    {
        for(size_t i = 0; i < oldClassesLength; i++)
        {
            free((void*)oldClasses[i]);
        }
        free(oldClasses);
    }
}

void kscrash_setCrashNotifyCallback(const KSReportWriteCallback onCrashNotify)
{
    KSLOG_TRACE("Set onCrashNotify to %p", onCrashNotify);
    crashContext()->config.onCrashNotify = onCrashNotify;
}
