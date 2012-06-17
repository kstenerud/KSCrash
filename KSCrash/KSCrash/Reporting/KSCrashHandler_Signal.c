//
//  KSCrashHandler_Signal.c
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


#include "KSCrashHandler_Signal.h"

#include "KSCrashHandler_Common.h"
#include "KSLogger.h"
#include "KSMach.h"
#include "KSSignalInfo.h"

#include <errno.h>
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>


/** Flag noting if we've installed our custom handlers or not.
 * It's not fully thread safe, but it's safer than locking and slightly better
 * than nothing.
 */
static volatile sig_atomic_t g_installed = 0;

/** Our custom signal stack. The signal handler will use this as its stack. */
static stack_t g_signalStack = {0};

/** Signal handlers that were installed before we installed ours. */
static struct sigaction* g_previousSignalHandlers = NULL;

/** Context to fill with crash information. */
static KSCrashContext* g_crashContext;

/** Called when a crash occurs. */
void(*kssighndl_i_onCrash)();


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
                            void* userContext);


void kssighndl_i_handleSignal(int sigNum,
                            siginfo_t* signalInfo,
                            void* userContext)
{
    // This is as close to atomic test-and-set we can get on iOS since
    // iOS devices don't handle OSAtomicTestAndSetBarrier properly.
    static volatile sig_atomic_t called = 0;
    if(!called)
    {
        called = 1;
        
        bool suspendSuccessful = ksmach_suspendAllThreads();
        
        kscrash_uninstallAsyncSafeHandlers();
        
        // Don't report if another handler has already.
        if(!g_crashContext->crashed)
        {
            g_crashContext->crashed = true;
            
            if(suspendSuccessful)
            {
                // We might get here via abort() in the NSException handler.
                if(g_crashContext->crashType != KSCrashTypeNSException)
                {
                    g_crashContext->crashType = KSCrashTypeSignal;
                    g_crashContext->faultAddress = (uintptr_t)signalInfo->si_addr;
                }
                g_crashContext->signalUserContext = userContext;
                g_crashContext->signalInfo = signalInfo;
                
                kssighndl_i_onCrash();
            }
        }
        
        if(suspendSuccessful)
        {
            ksmach_resumeAllThreads();
        }
        
        // Re-raise the signal so that the previous handlers can deal with it.
        // This is technically not allowed, but it works in OSX and iOS.
        raise(sigNum);
        return;
    }
    
    // Another signal was raised before we could restore the default handlers.
    // Log and ignore it, letting the first signal handler run to completion
    // (or at least past restoring the default handlers!)
    KSLOG_ERROR("Called again before the original handlers were restored: Signal %d, code %d",
                signalInfo->si_signo, signalInfo->si_code);
}

bool kscrash_installSignalHandler(KSCrashContext* const context,
                                  void(*onCrash)())
{
    if(!g_installed)
    {
        // Guarding against double-calls is more important than guarding against
        // reciprocal calls.
        g_installed = 1;
        
        g_crashContext = context;
        kssighndl_i_onCrash = onCrash;
        
        if(g_signalStack.ss_size == 0)
        {
            g_signalStack.ss_size = SIGSTKSZ;
            g_signalStack.ss_sp = malloc(g_signalStack.ss_size);
        }
        
        if(sigaltstack(&g_signalStack, NULL) != 0)
        {
            KSLOG_ERROR("signalstack: %s", strerror(errno));
            g_installed = 0;
            return false;
        }
        
        const int* fatalSignals = kssignal_fatalSignals();
        int numSignals = kssignal_numFatalSignals();
        
        if(g_previousSignalHandlers == NULL)
        {
            g_previousSignalHandlers = malloc(sizeof(*g_previousSignalHandlers)
                                              * (unsigned)numSignals);
        }
        
        struct sigaction action = {{0}};
        action.sa_flags = SA_SIGINFO | SA_ONSTACK;
#ifdef __LP64__
        action.sa_flags |= SA_64REGSET;
#endif
        sigemptyset(&action.sa_mask);
        action.sa_sigaction = &kssighndl_i_handleSignal;
        
        for(int i = 0; i < (int)numSignals; i++)
        {
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
                g_installed = 0;
                return false;
            }
        }
    }
    return true;
}

void kscrash_uninstallSignalHandler(void)
{
    if(g_installed)
    {
        // Guarding against double-calls is more important than guarding against
        // reciprocal calls.
        g_installed = 0;
        
        const int* fatalSignals = kssignal_fatalSignals();
        int numSignals = kssignal_numFatalSignals();
        
        for(int i = 0; i < numSignals; i++)
        {
            sigaction(fatalSignals[i], &g_previousSignalHandlers[i], NULL);
        }
    }
}

