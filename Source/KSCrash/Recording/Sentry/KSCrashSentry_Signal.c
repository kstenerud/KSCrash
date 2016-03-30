//
//  KSCrashSentry_Signal.c
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

#include <TargetConditionals.h>

#include "KSCrashSentry_Signal.h"
#include "KSCrashSentry_Private.h"

#include "KSSignalInfo.h"
#include "KSMach.h"

//#define KSLogger_LocalLevel TRACE
#include "KSLogger.h"

#include <errno.h>
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>


// ============================================================================
#pragma mark - Globals -
// ============================================================================

/** Flag noting if we've installed our custom handlers or not.
 * It's not fully thread safe, but it's safer than locking and slightly better
 * than nothing.
 */
static volatile sig_atomic_t g_installed = 0;

#if !TARGET_OS_TV
/** Our custom signal stack. The signal handler will use this as its stack. */
static stack_t g_signalStack = {0};
#endif

/** Signal handlers that were installed before we installed ours. */
static struct sigaction* g_previousSignalHandlers = NULL;

/** Context to fill with crash information. */
static KSCrash_SentryContext* g_context;


// ============================================================================
#pragma mark - Callbacks -
// ============================================================================

// Avoiding static functions due to linker issues.

/** Our custom signal handler.
 * Restore the default signal handlers, record the signal information, and
 * write a crash report.
 * Once we're done, re-raise the signal and let the default handlers deal with
 * it.
 *
 * @param signal The signal that was raised.
 *
 * @param signalInfo Information about the signal.
 *
 * @param userContext Other contextual information.
 */
void kssighndl_i_handleSignal(int sigNum,
                              siginfo_t* signalInfo,
                              void* userContext)
{
    KSLOG_DEBUG("Trapped signal %d", sigNum);
    if(g_installed)
    {
        bool wasHandlingCrash = g_context->handlingCrash;
        kscrashsentry_beginHandlingCrash(g_context);

        KSLOG_DEBUG("Signal handler is installed. Continuing signal handling.");

        KSLOG_DEBUG("Suspending all threads.");
        kscrashsentry_suspendThreads();

        if(wasHandlingCrash)
        {
            KSLOG_INFO("Detected crash in the crash reporter. Restoring original handlers.");
            g_context->crashedDuringCrashHandling = true;
            kscrashsentry_uninstall(KSCrashTypeAsyncSafe);
        }


        KSLOG_DEBUG("Filling out context.");
        g_context->crashType = KSCrashTypeSignal;
        g_context->offendingThread = ksmach_thread_self();
        g_context->registersAreValid = true;
        g_context->faultAddress = (uintptr_t)signalInfo->si_addr;
        g_context->signal.userContext = userContext;
        g_context->signal.signalInfo = signalInfo;


        KSLOG_DEBUG("Calling main crash handler.");
        g_context->onCrash();


        KSLOG_DEBUG("Crash handling complete. Restoring original handlers.");
        kscrashsentry_uninstall(KSCrashTypeAsyncSafe);
        kscrashsentry_resumeThreads();
    }

    KSLOG_DEBUG("Re-raising signal for regular handlers to catch.");
    // This is technically not allowed, but it works in OSX and iOS.
    raise(sigNum);
}


// ============================================================================
#pragma mark - API -
// ============================================================================

bool kscrashsentry_installSignalHandler(KSCrash_SentryContext* context)
{
    KSLOG_DEBUG("Installing signal handler.");

    if(g_installed)
    {
        KSLOG_DEBUG("Signal handler already installed.");
        return true;
    }
    g_installed = 1;

    g_context = context;

#if !TARGET_OS_TV
    if(g_signalStack.ss_size == 0)
    {
        KSLOG_DEBUG("Allocating signal stack area.");
        g_signalStack.ss_size = SIGSTKSZ;
        g_signalStack.ss_sp = malloc(g_signalStack.ss_size);
    }

    KSLOG_DEBUG("Setting signal stack area.");
    if(sigaltstack(&g_signalStack, NULL) != 0)
    {
        KSLOG_ERROR("signalstack: %s", strerror(errno));
        goto failed;
    }
#endif

    const int* fatalSignals = kssignal_fatalSignals();
    int fatalSignalsCount = kssignal_numFatalSignals();

    if(g_previousSignalHandlers == NULL)
    {
        KSLOG_DEBUG("Allocating memory to store previous signal handlers.");
        g_previousSignalHandlers = malloc(sizeof(*g_previousSignalHandlers)
                                          * (unsigned)fatalSignalsCount);
    }

    struct sigaction action = {{0}};
    action.sa_flags = SA_SIGINFO | SA_ONSTACK;
#ifdef __LP64__
    action.sa_flags |= SA_64REGSET;
#endif
    sigemptyset(&action.sa_mask);
    action.sa_sigaction = &kssighndl_i_handleSignal;

    for(int i = 0; i < fatalSignalsCount; i++)
    {
        KSLOG_DEBUG("Assigning handler for signal %d", fatalSignals[i]);
        if(sigaction(fatalSignals[i], &action, &g_previousSignalHandlers[i]) != 0)
        {
            char sigNameBuff[30];
            const char* sigName = kssignal_signalName(fatalSignals[i]);
            if(sigName == NULL)
            {
                snprintf(sigNameBuff, sizeof(sigNameBuff), "%d", fatalSignals[i]);
                sigName = sigNameBuff;
            }
            KSLOG_ERROR("sigaction (%s): %s", sigName, strerror(errno));
            // Try to reverse the damage
            for(i--;i >= 0; i--)
            {
                sigaction(fatalSignals[i], &g_previousSignalHandlers[i], NULL);
            }
            goto failed;
        }
    }
    KSLOG_DEBUG("Signal handlers installed.");
    return true;

failed:
    KSLOG_DEBUG("Failed to install signal handlers.");
    g_installed = 0;
    return false;
}

void kscrashsentry_uninstallSignalHandler(void)
{
    KSLOG_DEBUG("Uninstalling signal handlers.");
    if(!g_installed)
    {
        KSLOG_DEBUG("Signal handlers were already uninstalled.");
        return;
    }

    const int* fatalSignals = kssignal_fatalSignals();
    int fatalSignalsCount = kssignal_numFatalSignals();

    for(int i = 0; i < fatalSignalsCount; i++)
    {
        KSLOG_DEBUG("Restoring original handler for signal %d", fatalSignals[i]);
        sigaction(fatalSignals[i], &g_previousSignalHandlers[i], NULL);
    }
    
    KSLOG_DEBUG("Signal handlers uninstalled.");
    g_installed = 0;
}

