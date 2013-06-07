//
//  KSCrashSentry_CPPException.c
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

#include "KSCrashSentry_CPPException.h"
#include "KSCrashSentry_Private.h"

//#define KSLogger_LocalLevel TRACE
#include "KSLogger.h"

#include <dlfcn.h>
#include <execinfo.h>
#include <exception>
#include <mach/mach.h>
#include <stdlib.h>
#include <typeinfo>


#define STACKTRACE_BUFFER_LENGTH 30


// Compiler hints for "if" statements
#define likely_if(x) if(__builtin_expect(x,1))
#define unlikely_if(x) if(__builtin_expect(x,0))


// ============================================================================
#pragma mark - Globals -
// ============================================================================

/** True if this handler has been installed.
 * Note: We are not using sig_atomic or volatile since c++ exceptions can happen
 * quite frequently.
 */
static bool g_installed = false;

/** Buffer for the backtrace of the most recent exception. */
static uintptr_t g_stackTrace[STACKTRACE_BUFFER_LENGTH];

/** Number of backtrace entries in the most recent exception. */
static int g_stackTraceCount = 0;

/** Context to fill with crash information. */
static KSCrash_SentryContext* g_context;


// ============================================================================
#pragma mark - Callbacks -
// ============================================================================

typedef void (*cxa_throw_type)(void*, void*, void (*)(void*));

extern "C" void __cxa_throw(void* thrown_exception, void* tinfo, void (*dest)(void*))
{
    if(g_installed)
    {
        g_stackTraceCount = backtrace((void**)g_stackTrace, sizeof(g_stackTrace) / sizeof(*g_stackTrace));
    }

    static cxa_throw_type orig_cxa_throw = NULL;
    unlikely_if(orig_cxa_throw == NULL)
    {
        orig_cxa_throw = (cxa_throw_type) dlsym(RTLD_NEXT, "__cxa_throw");
    }
    orig_cxa_throw(thrown_exception, tinfo, dest);
}


static void CPPExceptionTerminate_Installed(void)
{
    KSLOG_DEBUG("Trapped c++ exception %s", g_exception_cause);
    bool wasHandlingCrash = g_context->handlingCrash;
    kscrashsentry_beginHandlingCrash(g_context);

    KSLOG_DEBUG("Exception handler is installed. Continuing exception handling.");

    if(wasHandlingCrash)
    {
        KSLOG_INFO("Detected crash in the crash reporter. Restoring original handlers.");
        g_context->crashedDuringCrashHandling = true;
        kscrashsentry_uninstall((KSCrashType)KSCrashTypeAll);
    }

    KSLOG_DEBUG(@"Suspending all threads.");
    kscrashsentry_suspendThreads();

    g_context->crashType = KSCrashTypeCPPException;
    g_context->offendingThread = mach_thread_self();
    g_context->registersAreValid = false;
    g_context->stackTrace = g_stackTrace + 1; // Don't record __cxa_throw
    g_context->stackTraceLength = g_stackTraceCount - 1;

    KSLOG_DEBUG(@"Calling main crash handler.");
    g_context->onCrash();

    KSLOG_DEBUG(@"Crash handling complete. Restoring original handlers.");
    kscrashsentry_uninstall((KSCrashType)KSCrashTypeAll);
    abort();
}

static void CPPExceptionTerminate_Uninstalled(void)
{
    abort();
}


// ============================================================================
#pragma mark - Public API -
// ============================================================================

extern "C" bool kscrashsentry_installCPPExceptionHandler(KSCrash_SentryContext* context)
{
    KSLOG_DEBUG("Installing C++ exception handler.");

    if(g_installed)
    {
        KSLOG_DEBUG("C++ exception handler already installed.");
        return true;
    }
    g_installed = true;

    g_context = context;

    std::set_terminate(CPPExceptionTerminate_Installed);
    return true;
}

extern "C" void kscrashsentry_uninstallCPPExceptionHandler(void)
{
    KSLOG_DEBUG("Uninstalling C++ exception handlers.");
    if(!g_installed)
    {
        KSLOG_DEBUG("C++ exception handlers were already uninstalled.");
        return;
    }

    std::set_terminate(CPPExceptionTerminate_Uninstalled);
    g_installed = false;
}
