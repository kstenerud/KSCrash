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
#include "Demangle.h"
#include "KSMach.h"

//#define KSLogger_LocalLevel TRACE
#include "KSLogger.h"

#include <cxxabi.h>
#include <dlfcn.h>
#include <exception>
#include <execinfo.h>
#include <stdio.h>
#include <stdlib.h>
#include <typeinfo>


#define STACKTRACE_BUFFER_LENGTH 30
#define DEMANGLE_BUFFER_LENGTH 2000
#define DESCRIPTION_BUFFER_LENGTH 1000


// Compiler hints for "if" statements
#define likely_if(x) if(__builtin_expect(x,1))
#define unlikely_if(x) if(__builtin_expect(x,0))


// ============================================================================
#pragma mark - Globals -
// ============================================================================

/** True if this handler has been installed. */
static volatile sig_atomic_t g_installed = 0;

/** True if the handler should capture the next stack trace. */
static bool g_captureNextStackTrace = false;

static std::terminate_handler g_originalTerminateHandler;

/** Buffer for the backtrace of the most recent exception. */
static uintptr_t g_stackTrace[STACKTRACE_BUFFER_LENGTH];

/** Number of backtrace entries in the most recent exception. */
static int g_stackTraceCount = 0;

/** Context to fill with crash information. */
static KSCrash_SentryContext* g_context;


// ============================================================================
#pragma mark - Callbacks -
// ============================================================================

typedef void (*cxa_throw_type)(void*, std::type_info*, void (*)(void*));

extern "C" void __cxa_throw(void* thrown_exception, std::type_info* tinfo, void (*dest)(void*))
{
    if(g_captureNextStackTrace)
    {
        g_stackTraceCount = backtrace((void**)g_stackTrace, sizeof(g_stackTrace) / sizeof(*g_stackTrace));
    }

    static cxa_throw_type orig_cxa_throw = NULL;
    unlikely_if(orig_cxa_throw == NULL)
    {
        orig_cxa_throw = (cxa_throw_type) dlsym(RTLD_NEXT, "__cxa_throw");
    }
    orig_cxa_throw(thrown_exception, tinfo, dest);
    __builtin_unreachable();
}


static void CPPExceptionTerminate(void)
{
    KSLOG_DEBUG(@"Trapped c++ exception");

    bool isNSException = false;
    char nameDemangled[DEMANGLE_BUFFER_LENGTH];
    char descriptionBuff[DESCRIPTION_BUFFER_LENGTH];
    const char* name = NULL;
    const char* description = NULL;

    KSLOG_DEBUG(@"Get exception type name.");
    std::type_info* tinfo = __cxxabiv1::__cxa_current_exception_type();
    if(tinfo != NULL)
    {
        name = tinfo->name();
        if(safe_demangle(name, nameDemangled, sizeof(nameDemangled)) == DEMANGLE_STATUS_SUCCESS)
        {
            name = nameDemangled;
        }
    }

    description = descriptionBuff;
    descriptionBuff[0] = 0;

    KSLOG_DEBUG(@"Discovering what kind of exception was thrown.");
    g_captureNextStackTrace = false;
    try
    {
        throw;
    }
    catch(NSException* exception)
    {
        KSLOG_DEBUG(@"Detected NSException. Letting the current NSException handler deal with it.");
        isNSException = true;
    }
    catch(std::exception& exc)
    {
        strncpy(descriptionBuff, exc.what(), sizeof(descriptionBuff));
    }
#define CATCH_VALUE(TYPE, PRINTFTYPE) \
catch(TYPE value)\
{ \
    snprintf(descriptionBuff, sizeof(descriptionBuff), "%" #PRINTFTYPE, value); \
}
    CATCH_VALUE(char,                 d)
    CATCH_VALUE(short,                d)
    CATCH_VALUE(int,                  d)
    CATCH_VALUE(long,                ld)
    CATCH_VALUE(long long,          lld)
    CATCH_VALUE(unsigned char,        u)
    CATCH_VALUE(unsigned short,       u)
    CATCH_VALUE(unsigned int,         u)
    CATCH_VALUE(unsigned long,       lu)
    CATCH_VALUE(unsigned long long, llu)
    CATCH_VALUE(float,                f)
    CATCH_VALUE(double,               f)
    CATCH_VALUE(long double,         Lf)
    CATCH_VALUE(char*,                s)
    CATCH_VALUE(const char*,          s)
    catch(...)
    {
        description = NULL;
    }
    g_captureNextStackTrace = (g_installed != 0);

    if(!isNSException)
    {
        bool wasHandlingCrash = g_context->handlingCrash;
        kscrashsentry_beginHandlingCrash(g_context);

        if(wasHandlingCrash)
        {
            KSLOG_INFO(@"Detected crash in the crash reporter. Restoring original handlers.");
            g_context->crashedDuringCrashHandling = true;
            kscrashsentry_uninstall((KSCrashType)KSCrashTypeAll);
        }

        KSLOG_DEBUG(@"Suspending all threads.");
        kscrashsentry_suspendThreads();

        g_context->crashType = KSCrashTypeCPPException;
        g_context->offendingThread = ksmach_thread_self();
        g_context->registersAreValid = false;
        g_context->stackTrace = g_stackTrace + 1; // Don't record __cxa_throw stack entry
        g_context->stackTraceLength = g_stackTraceCount - 1;
        g_context->CPPException.name = name;
        g_context->crashReason = description;

        KSLOG_DEBUG(@"Calling main crash handler.");
        g_context->onCrash();

        KSLOG_DEBUG(@"Crash handling complete. Restoring original handlers.");
        kscrashsentry_uninstall((KSCrashType)KSCrashTypeAll);
        kscrashsentry_resumeThreads();
    }

    g_originalTerminateHandler();
}


// ============================================================================
#pragma mark - Public API -
// ============================================================================

extern "C" bool kscrashsentry_installCPPExceptionHandler(KSCrash_SentryContext* context)
{
    KSLOG_DEBUG(@"Installing C++ exception handler.");

    if(g_installed)
    {
        KSLOG_DEBUG(@"C++ exception handler already installed.");
        return true;
    }
    g_installed = 1;

    g_context = context;

    g_originalTerminateHandler = std::set_terminate(CPPExceptionTerminate);
    g_captureNextStackTrace = true;
    return true;
}

extern "C" void kscrashsentry_uninstallCPPExceptionHandler(void)
{
    KSLOG_DEBUG(@"Uninstalling C++ exception handler.");
    if(!g_installed)
    {
        KSLOG_DEBUG(@"C++ exception handler already uninstalled.");
        return;
    }

    g_captureNextStackTrace = false;
    std::set_terminate(g_originalTerminateHandler);
    g_installed = 0;
}
