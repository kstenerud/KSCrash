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
#include "KSCrashReportStore.h"
#include "KSCrashSentry_Deadlock.h"
#include "KSCrashSentry_User.h"
#include "KSFileUtils.h"
#include "KSObjC.h"
#include "KSString.h"
#include "KSSystemInfo.h"
#include "KSZombie.h"

//#define KSLogger_LocalLevel TRACE
#include "KSLogger.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <uuid/uuid.h>


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

static char* g_logFilePath;


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
    char crashReportFilePath[KSFU_MAX_PATH_LENGTH];
    kscrs_getCrashReportPath(crashReportFilePath);

    if(context->crash.crashedDuringCrashHandling)
    {
        kscrashreport_writeRecrashReport(context, crashReportFilePath);
    }
    else
    {
        kscrashreport_writeStandardReport(context, crashReportFilePath);
    }
}


// ============================================================================
#pragma mark - API -
// ============================================================================

KSCrashType kscrash_install(const char* appName, const char* const installPath)
{
    KSLOG_DEBUG("Installing crash reporter.");

    KSCrash_Context* context = crashContext();

    if(g_installed)
    {
        KSLOG_DEBUG("Crash reporter already installed.");
        return context->config.handlingCrashTypes;
    }
    g_installed = 1;

    char path[KSFU_MAX_PATH_LENGTH];
    snprintf(path, sizeof(path), "%s/Reports", installPath);
    ksfu_makePath(path);
    kscrs_initialize(appName, path);

    snprintf(path, sizeof(path), "%s/Data", installPath);
    ksfu_makePath(path);
    snprintf(path, sizeof(path), "%s/Data/CrashState.json", installPath);
    if(!kscrashstate_init(path, &context->state))
    {
        KSLOG_ERROR("Failed to initialize persistent crash state");
    }

    snprintf(path, sizeof(path), "%s/Data/ConsoleLog.txt", installPath);
    g_logFilePath = strdup(path);

    if(context->config.introspectionRules.enabled)
    {
        ksobjc_init();
    }
    
    kscrash_reinstall();


    KSCrashType crashTypes = kscrash_setHandlingCrashTypes(context->config.handlingCrashTypes);

    context->config.systemInfoJSON = kssysteminfo_toJSON();
    context->config.processName = kssysteminfo_copyProcessName();

    KSLOG_DEBUG("Installation complete.");
    return crashTypes;
}

void kscrash_reinstall()
{
    uuid_t uuid;
    uuid_generate(uuid);
    static char crashID[37];
    sprintf(crashID, "%02X%02X%02X%02X-%02X%02X-%02X%02X-%02X%02X-%02X%02X%02X%02X%02X%02X",
            (unsigned)uuid[0],
            (unsigned)uuid[1],
            (unsigned)uuid[2],
            (unsigned)uuid[3],
            (unsigned)uuid[4],
            (unsigned)uuid[5],
            (unsigned)uuid[6],
            (unsigned)uuid[7],
            (unsigned)uuid[8],
            (unsigned)uuid[9],
            (unsigned)uuid[10],
            (unsigned)uuid[11],
            (unsigned)uuid[12],
            (unsigned)uuid[13],
            (unsigned)uuid[14],
            (unsigned)uuid[15]
            );
    KSCrash_Context* context = crashContext();
    ksstring_replace(&context->config.crashID, crashID);
    KSLOG_TRACE("crashID = %s", crashID);

    kscrashstate_reset();
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

void kscrash_setDoNotIntrospectClasses(const char** doNotIntrospectClasses, int length)
{
    const char** oldClasses = crashContext()->config.introspectionRules.restrictedClasses;
    int oldClassesLength = crashContext()->config.introspectionRules.restrictedClassesCount;
    const char** newClasses = NULL;
    int newClassesLength = 0;
    
    if(doNotIntrospectClasses != NULL && length > 0)
    {
        newClassesLength = length;
        newClasses = malloc(sizeof(*newClasses) * (unsigned)newClassesLength);
        if(newClasses == NULL)
        {
            KSLOG_ERROR("Could not allocate memory");
            return;
        }
        
        for(int i = 0; i < newClassesLength; i++)
        {
            newClasses[i] = strdup(doNotIntrospectClasses[i]);
        }
    }

    crashContext()->config.introspectionRules.restrictedClasses = newClasses;
    crashContext()->config.introspectionRules.restrictedClassesCount = newClassesLength;

    if(oldClasses != NULL)
    {
        for(int i = 0; i < oldClassesLength; i++)
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

bool kscrash_redirectConsoleLogToFile()
{
    return kslog_setLogFilename(g_logFilePath, true);
}

void kscrash_reportUserException(const char* name,
                                 const char* reason,
                                 const char* language,
                                 const char* lineOfCode,
                                 const char* stackTrace,
                                 bool terminateProgram)
{
    kscrashsentry_reportUserException(name,
                                      reason,
                                      language,
                                      lineOfCode,
                                      stackTrace,
                                      terminateProgram);

    // If kscrash_reportUserException() returns, we did not terminate.
    // Set up IDs and paths for the next crash.

    kscrsi_incrementCrashReportIndex();
    kscrash_reinstall();
}
