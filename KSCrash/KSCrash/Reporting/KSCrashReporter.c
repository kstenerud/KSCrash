//
//  KSCrashReporter.c
//
//  Created by Karl Stenerud on 12-01-28.
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


#include "KSCrashReporter.h"

#include "KSCrashHandler_MachException.h"
#include "KSCrashHandler_NSException.h"
#include "KSCrashHandler_Signal.h"
#include "KSCrashState.h"
#include "KSCrashReportWriter.h"
#include "KSLogger.h"
#include "KSSystemInfoC.h"

#include <errno.h>
#include <fcntl.h>
#include <mach/mach_time.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>


// Avoiding static functions due to linker issues.

/** Called when a crash occurs.
 *
 * This function gets passed as a callback to a crash handler.
 */
void kscrash_i_onCrash(void);


/** Single, global crash context. */
static KSCrashContext g_crashReportContext = {0};

/** Path to store the next crash report. */
static char* g_reportFilePath;

/** Path to store the state file. */
static char* g_stateFilePath;


void kscrash_i_onCrash(void)
{
    kscrash_notifyApplicationCrash();
    KSCrashContext* crashContext = &g_crashReportContext;
    KSLOGBASIC_INFO("Writing crash report to %s", g_reportFilePath);
    
    kscrash_writeCrashReport(crashContext, g_reportFilePath);
}

bool kscrash_installReporter(const char* const reportFilePath,
                             const char* const stateFilePath,
                             const char* const crashID,
                             const char* const userInfoJSON,
                             const bool printTraceToStdout,
                             const KSReportWriteCallback onCrashNotify)
{
    static volatile sig_atomic_t initialized = 0;
    if(!initialized)
    {
        initialized = 1;
        
        g_stateFilePath = strdup(stateFilePath);
        g_reportFilePath = strdup(reportFilePath);
        KSCrashContext* context = &g_crashReportContext;
        
        if(!kscrash_initState(g_stateFilePath, context))
        {
            KSLOG_ERROR("Failed to initialize persistent crash state");
            // Don't bail because we can still generate reports without this
        }
        context->appLaunchTime = mach_absolute_time();
        
        if(!kscrash_installSignalHandler(context, kscrash_i_onCrash))
        {
            // If we fail to install the signal handlers, all is lost.
            KSLOG_ERROR("Failed to install signal handler");
            free(g_stateFilePath);
            g_stateFilePath = NULL;
            free(g_reportFilePath);
            g_reportFilePath = NULL;
            initialized = 0;
            return false;
        }
        
        // We can still generate reports in many cases if the NSException and
        // mach exception handlers fail to install.
        kscrash_installNSExceptionHandler(context, kscrash_i_onCrash);
        kscrash_installMachExceptionHandler(context, kscrash_i_onCrash);
        
        context->printTraceToStdout = printTraceToStdout;
        context->systemInfoJSON = kssysteminfo_toJSON();
        if(userInfoJSON != NULL)
        {
            context->userInfoJSON = strdup(userInfoJSON);
        }
        context->crashID = strdup(crashID);
        context->onCrashNotify = onCrashNotify;
        
        return true;
    }
    
    KSLOG_ERROR("Called more than once");
    return false;
}

