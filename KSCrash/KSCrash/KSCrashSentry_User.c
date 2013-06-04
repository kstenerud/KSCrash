//
//  KSCrashSentry_User.c
//  KSCrash
//
//  Created by Karl Stenerud on 6/4/13.
//  Copyright (c) 2013 Karl Stenerud. All rights reserved.
//

#include "KSCrashSentry_User.h"
#include "KSCrashSentry_Private.h"

//#define KSLogger_LocalLevel TRACE
#include "KSLogger.h"

#include <execinfo.h>
#include <mach/mach.h>
#include <stdlib.h>


/** Context to fill with crash information. */
static KSCrash_SentryContext* g_context;


bool kscrashsentry_installUserExceptionHandler(KSCrash_SentryContext* const context)
{
    KSLOG_DEBUG("Installing user exception handler.");
    g_context = context;
    return true;
}

void kscrashsentry_uninstallUserExceptionHandler(void)
{
    KSLOG_DEBUG("Uninstalling user exception handler.");
    g_context = NULL;
}

void kscrashsentry_reportUserException(const char* name,
                                       const char* reason,
                                       const char* lineOfCode,
                                       const char** stackTrace,
                                       size_t stackTraceCount,
                                       bool terminateProgram)
{
    if(g_context != NULL)
    {
        KSLOG_DEBUG("Suspending all threads");
        kscrashsentry_suspendThreads();

        KSLOG_DEBUG("Fetching call stack.");
        int callstackCount = 100;
        uintptr_t callstack[callstackCount];
        callstackCount = backtrace((void**)callstack, callstackCount);
        if(callstackCount <= 0)
        {
            KSLOG_ERROR("backtrace() returned call stack length of %d", callstackCount);
            callstackCount = 0;
        }

        KSLOG_DEBUG("Filling out context.");
        g_context->crashType = KSCrashTypeUserReported;
        g_context->offendingThread = mach_thread_self();
        g_context->registersAreValid = false;
        g_context->crashReason = reason;
        g_context->stackTrace = callstack;
        g_context->stackTraceLength = callstackCount;
        g_context->userException.name = name;
        g_context->userException.lineOfCode = lineOfCode;
        g_context->userException.customStackTrace = stackTrace;
        g_context->userException.customStackTraceLength = (int)stackTraceCount;

        KSLOG_DEBUG("Calling main crash handler.");
        g_context->onCrash();

        if(terminateProgram)
        {
            kscrashsentry_uninstall(KSCrashTypeAll);
            kscrashsentry_resumeThreads();
            abort();
        }
        else
        {
            kscrashsentry_resumeThreads();
        }
    }
}
