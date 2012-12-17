//
//  KSCrashSentry.c
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


#include "KSCrashSentry.h"
#include "KSCrashSentry_Private.h"

#include "KSCrashSentry_Deadlock.h"
#include "KSCrashSentry_MachException.h"
#include "KSCrashSentry_NSException.h"
#include "KSCrashSentry_Signal.h"
#include "KSMach.h"

//#define KSLogger_LocalLevel TRACE
#include "KSLogger.h"


// ============================================================================
#pragma mark - Globals -
// ============================================================================

/** Context to fill with crash information. */
static KSCrash_SentryContext* g_context = NULL;

/** Keeps track of whether threads have already been suspended or not.
 * This won't handle multiple suspends in a row.
 */
static bool g_threads_are_running = true;


// ============================================================================
#pragma mark - API -
// ============================================================================

KSCrashType kscrashsentry_installWithContext(KSCrash_SentryContext* context,
                                             KSCrashType crashTypes)
{
    KSLOG_DEBUG("Installing handlers with context %p, crash types 0x%x.", context, crashTypes);
    g_context = context;

    context->handlingCrash = false;

    KSCrashType installed = 0;
    if((crashTypes & KSCrashTypeMainThreadDeadlock) && kscrashsentry_installDeadlockHandler(context))
    {
        installed |= KSCrashTypeMainThreadDeadlock;
    }
    if((crashTypes & KSCrashTypeMachException) && kscrashsentry_installMachHandler(context))
    {
        installed |= KSCrashTypeMachException;
    }
    if((crashTypes & KSCrashTypeSignal) && kscrashsentry_installSignalHandler(context))
    {
        installed |= KSCrashTypeSignal;
    }
    if((crashTypes & KSCrashTypeNSException) && kscrashsentry_installNSExceptionHandler(context))
    {
        installed |= KSCrashTypeNSException;
    }
    
    KSLOG_DEBUG("Installation complete. Installed types 0x%x.", installed);
    return installed;
}

void kscrashsentry_uninstall(KSCrashType crashTypes)
{
    KSLOG_DEBUG("Uninstalling handlers with crash types 0x%x.", crashTypes);
    if(crashTypes & KSCrashTypeMainThreadDeadlock)
    {
        kscrashsentry_uninstallDeadlockHandler();
    }
    if(crashTypes & KSCrashTypeMachException)
    {
        kscrashsentry_uninstallMachHandler();
    }
    if(crashTypes & KSCrashTypeSignal)
    {
        kscrashsentry_uninstallSignalHandler();
    }
    if(crashTypes & KSCrashTypeNSException)
    {
        kscrashsentry_uninstallNSExceptionHandler();
    }
    KSLOG_DEBUG("Uninstall complete.");
}


// ============================================================================
#pragma mark - Private API -
// ============================================================================

void kscrashsentry_suspendThreads(void)
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

void kscrashsentry_resumeThreads(void)
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
