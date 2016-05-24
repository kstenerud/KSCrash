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
#include "KSString.h"
#include "KSMach.h"
#include "KSObjC.h"
#include "KSSignalInfo.h"
#include "KSSystemInfoC.h"
#include "KSZombie.h"
#include "KSCrashSentry_Deadlock.h"
#include "KSCrashSentry_User.h"

//#define KSLogger_LocalLevel TRACE
#include "KSLogger.h"

#include <errno.h>
#include <execinfo.h>
#include <fcntl.h>
#include <mach/mach_time.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>


// ============================================================================
#pragma mark - Globals -
// ============================================================================

/** True if KSCrash has been installed. */
static volatile sig_atomic_t g_installed = 0;

/** Single, global crash context. */
static KSCrash_Context g_crashReportContext =
{
    .config =
    {
        .handlingCrashTypes = KSCrashTypeProductionSafe
    }
};

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

KSCrashType kscrash_install(const char* const crashReportFilePath,
                            const char* const recrashReportFilePath,
                            const char* stateFilePath,
                            const char* crashID)
{
    KSLOG_DEBUG("Installing crash reporter.");

    KSCrash_Context* context = crashContext();

    if(g_installed)
    {
        KSLOG_DEBUG("Crash reporter already installed.");
        return context->config.handlingCrashTypes;
    }
    g_installed = 1;

    ksmach_init();
    
    if(context->config.introspectionRules.enabled)
    {
        ksobjc_init();
    }
    
    kscrash_reinstall(crashReportFilePath,
                      recrashReportFilePath,
                      stateFilePath,
                      crashID);


    KSCrashType crashTypes = kscrash_setHandlingCrashTypes(context->config.handlingCrashTypes);

    context->config.systemInfoJSON = kssysteminfo_toJSON();
    context->config.processName = kssysteminfo_copyProcessName();

    KSLOG_DEBUG("Installation complete.");
    return crashTypes;
}

void kscrash_reinstall(const char* const crashReportFilePath,
                       const char* const recrashReportFilePath,
                       const char* const stateFilePath,
                       const char* const crashID)
{
    KSLOG_TRACE("reportFilePath = %s", crashReportFilePath);
    KSLOG_TRACE("secondaryReportFilePath = %s", recrashReportFilePath);
    KSLOG_TRACE("stateFilePath = %s", stateFilePath);
    KSLOG_TRACE("crashID = %s", crashID);

    ksstring_replace((const char**)&g_stateFilePath, stateFilePath);
    ksstring_replace((const char**)&g_crashReportFilePath, crashReportFilePath);
    ksstring_replace((const char**)&g_recrashReportFilePath, recrashReportFilePath);
    KSCrash_Context* context = crashContext();
    ksstring_replace(&context->config.crashID, crashID);

    if(!kscrashstate_init(g_stateFilePath, &context->state))
    {
        KSLOG_ERROR("Failed to initialize persistent crash state");
    }
    context->state.appLaunchTime = mach_absolute_time();
}

KSCrashType kscrash_setHandlingCrashTypes(KSCrashType crashTypes)
{
    KSCrash_Context* context = crashContext();
    context->config.handlingCrashTypes = crashTypes;
    
    if(g_installed)
    {
        kscrashsentry_uninstall(~crashTypes);
        crashTypes = kscrashsentry_installWithContext(&context->crash, crashTypes, kscrash_i_onCrash);
    }

    return crashTypes;
}

void kscrash_setUserInfoJSON(const char* const userInfoJSON)
{
    KSLOG_TRACE("set userInfoJSON to %p", userInfoJSON);
    KSCrash_Context* context = crashContext();
    ksstring_replace(&context->config.userInfoJSON, userInfoJSON);
}

void kscrash_setDeadlockWatchdogInterval(double deadlockWatchdogInterval)
{
    kscrashsentry_setDeadlockHandlerWatchdogInterval(deadlockWatchdogInterval);
}

void kscrash_setPrintTraceToStdout(bool printTraceToStdout)
{
    crashContext()->config.printTraceToStdout = printTraceToStdout;
}

void kscrash_setSearchThreadNames(bool shouldSearchThreadNames)
{
    crashContext()->config.searchThreadNames = shouldSearchThreadNames;
}

void kscrash_setSearchQueueNames(bool shouldSearchQueueNames)
{
    crashContext()->config.searchQueueNames = shouldSearchQueueNames;
}

void kscrash_setIntrospectMemory(bool introspectMemory)
{
    crashContext()->config.introspectionRules.enabled = introspectMemory;
}

void kscrash_setCatchZombies(bool catchZombies)
{
    kszombie_setEnabled(catchZombies);
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

void kscrash_reportUserException(const char* name,
                                 const char* reason,
                                 const char* language,
                                 const char* lineOfCode,
                                 const char** stackTrace,
                                 size_t stackTraceCount,
                                 bool terminateProgram)
{
    kscrashsentry_reportUserException(name,
                                      reason,
                                      language,
                                      lineOfCode,
                                      stackTrace,
                                      stackTraceCount,
                                      terminateProgram);
}
