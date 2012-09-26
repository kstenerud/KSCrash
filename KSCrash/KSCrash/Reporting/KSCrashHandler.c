//
//  KSCrashHandler.c
//
//  Created by Karl Stenerud on 12-02-12.
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


#include "KSCrashHandler.h"

#include "KSCrashHandler_MachException.h"
#include "KSCrashHandler_NSException.h"
#include "KSCrashHandler_Signal.h"
#include "KSMach.h"

//#define KSLogger_LocalLevel TRACE
#include "KSLogger.h"


static KSCrash_HandlerContext* g_context = NULL;

static bool g_threads_are_running = true;


KSCrashType kscrash_handlers_installWithContext(KSCrash_HandlerContext* context,
                                                KSCrashType crashTypes)
{
    KSLOG_DEBUG("Installing handlers with context %p, crash types 0x%x.", context, crashTypes);
    g_context = context;

    context->handlingCrash = false;

    KSCrashType installed = 0;
    if((crashTypes & KSCrashTypeMachException) && kscrash_handlers_installMachHandler(context))
    {
        installed |= KSCrashTypeMachException;
    }
    if((crashTypes & KSCrashTypeSignal) && kscrash_handlers_installSignalHandler(context))
    {
        installed |= KSCrashTypeSignal;
    }
    if((crashTypes & KSCrashTypeNSException) && kscrash_handlers_installNSExceptionHandler(context))
    {
        installed |= KSCrashTypeNSException;
    }

    KSLOG_DEBUG("Installation complete. Installed types 0x%x.", installed);
    return installed;
}

void kscrash_handlers_uninstall(KSCrashType crashTypes)
{
    KSLOG_DEBUG("Uninstalling handlers with crash types 0x%x.", crashTypes);
    if(crashTypes & KSCrashTypeMachException)
    {
        kscrash_handlers_uninstallMachHandler();
    }
    if(crashTypes & KSCrashTypeSignal)
    {
        kscrash_handlers_uninstallSignalHandler();
    }
    if(crashTypes & KSCrashTypeNSException)
    {
        kscrash_handlers_uninstallNSExceptionHandler();
    }
    KSLOG_DEBUG("Uninstall complete.");
}

void kscrash_handlers_suspendThreads(void)
{
    KSLOG_DEBUG("Suspending threads.");
    if(!g_threads_are_running)
    {
        KSLOG_DEBUG("Threads already suspended.");
        return;
    }

    if(g_context != NULL)
    {
        int numThreads = sizeof(g_context->reservedThreads) / sizeof(g_context->reservedThreads[0]);
        KSLOG_DEBUG("Suspending all threads except for %d reserved threads.", numThreads);
        if(ksmach_suspendAllThreadsExcept(g_context->reservedThreads, numThreads))
        {
            KSLOG_DEBUG("Suspend successful.");
            g_threads_are_running = false;
        }
    }
    else
    {
        KSLOG_DEBUG("Suspending all threads.");
        if(ksmach_suspendAllThreads())
        {
            KSLOG_DEBUG("Suspend successful.");
            g_threads_are_running = false;
        }
    }
    KSLOG_DEBUG("Suspend complete.");
}

void kscrash_handlers_resumeThreads(void)
{
    KSLOG_DEBUG("Resuming threads.");
    if(g_threads_are_running)
    {
        KSLOG_DEBUG("Threads already resumed.");
        return;
    }

    if(g_context != NULL)
    {
        int numThreads = sizeof(g_context->reservedThreads) / sizeof(g_context->reservedThreads[0]);
        KSLOG_DEBUG("Resuming all threads except for %d reserved threads.", numThreads);
        if(ksmach_resumeAllThreadsExcept(g_context->reservedThreads, numThreads))
        {
            KSLOG_DEBUG("Resume successful.");
            g_threads_are_running = true;
        }
    }
    else
    {
        KSLOG_DEBUG("Resuming all threads.");
        if(ksmach_resumeAllThreads())
        {
            KSLOG_DEBUG("Resume successful.");
            g_threads_are_running = true;
        }
    }
    KSLOG_DEBUG("Resume complete.");
}
