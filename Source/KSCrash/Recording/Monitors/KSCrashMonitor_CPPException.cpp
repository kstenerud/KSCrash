//
//  KSCrashMonitor_CPPException.c
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

#include "KSCrashMonitor_CPPException.h"
#include "KSCrashMonitorContext.h"
#include "KSID.h"
#include "KSThread.h"
#include "KSMachineContext.h"
#include "KSStackCursor_SelfThread.h"

//#define KSLogger_LocalLevel TRACE
#include "KSLogger.h"

#include "KSCxaThrowSwapper.h"

#include <cxxabi.h>
#include <dlfcn.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <typeinfo>
#include <exception>

#define STACKTRACE_BUFFER_LENGTH 30
#define DESCRIPTION_BUFFER_LENGTH 1000


// Compiler hints for "if" statements
#define likely_if(x) if(__builtin_expect(x,1))
#define unlikely_if(x) if(__builtin_expect(x,0))


// ============================================================================
#pragma mark - Globals -
// ============================================================================

/** True if this handler has been installed. */
static volatile bool g_isEnabled = false;

/** True if the handler should capture the next stack trace. */
static bool g_captureNextStackTrace = false;

static bool g_cxaSwapEnabled = false;

static std::terminate_handler g_originalTerminateHandler;

static char g_eventID[37];

static KSCrash_MonitorContext g_monitorContext;

// TODO: Thread local storage is not supported < ios 9.
// Find some other way to do thread local. Maybe storage with lookup by tid?
static KSStackCursor g_stackCursor;

// ============================================================================
#pragma mark - Callbacks -
// ============================================================================

static void captureStackTrace(void*, std::type_info* tinfo, void (*)(void*))
{
    if (tinfo != nullptr && strcmp(tinfo->name(), "NSException") == 0)
    {
        return;
    }
    if(g_captureNextStackTrace)
    {
        kssc_initSelfThread(&g_stackCursor, 2);
    }
}

typedef void (*cxa_throw_type)(void*, std::type_info*, void (*)(void*));

extern "C"
{
    void __cxa_throw(void* thrown_exception, std::type_info* tinfo, void (*dest)(void*)) __attribute__ ((weak));

    void __cxa_throw(void* thrown_exception, std::type_info* tinfo, void (*dest)(void*))
    {
        static cxa_throw_type orig_cxa_throw = NULL;
        if (g_cxaSwapEnabled == false)
        {
            captureStackTrace(thrown_exception, tinfo, dest);
        }
        unlikely_if(orig_cxa_throw == NULL)
        {
            orig_cxa_throw = (cxa_throw_type) dlsym(RTLD_NEXT, "__cxa_throw");
        }
        orig_cxa_throw(thrown_exception, tinfo, dest);
        __builtin_unreachable();
    }
}

static void CPPExceptionTerminate(void)
{
    thread_act_array_t threads = NULL;
    mach_msg_type_number_t numThreads = 0;
    ksmc_suspendEnvironment(&threads, &numThreads);
    KSLOG_DEBUG("Trapped c++ exception");
    const char* name = NULL;
    std::type_info* tinfo = __cxxabiv1::__cxa_current_exception_type();
    if(tinfo != NULL)
    {
        name = tinfo->name();
    }
    
    if(name == NULL || strcmp(name, "NSException") != 0)
    {
        kscm_notifyFatalExceptionCaptured(false);
        KSCrash_MonitorContext* crashContext = &g_monitorContext;
        memset(crashContext, 0, sizeof(*crashContext));

        char descriptionBuff[DESCRIPTION_BUFFER_LENGTH];
        const char* description = descriptionBuff;
        descriptionBuff[0] = 0;

        KSLOG_DEBUG("Discovering what kind of exception was thrown.");
        g_captureNextStackTrace = false;
        try
        {
            throw;
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
        catch(...)
        {
            description = NULL;
        }
        g_captureNextStackTrace = g_isEnabled;

        // TODO: Should this be done here? Maybe better in the exception handler?
        KSMC_NEW_CONTEXT(machineContext);
        ksmc_getContextForThread(ksthread_self(), machineContext, true);

        KSLOG_DEBUG("Filling out context.");
        crashContext->crashType = KSCrashMonitorTypeCPPException;
        crashContext->eventID = g_eventID;
        crashContext->registersAreValid = false;
        crashContext->stackCursor = &g_stackCursor;
        crashContext->CPPException.name = name;
        crashContext->exceptionName = name;
        crashContext->crashReason = description;
        crashContext->offendingMachineContext = machineContext;

        kscm_handleException(crashContext);
    }
    else
    {
        KSLOG_DEBUG("Detected NSException. Letting the current NSException handler deal with it.");
    }
    ksmc_resumeEnvironment(threads, numThreads);

    KSLOG_DEBUG("Calling original terminate handler.");
    g_originalTerminateHandler();
}


// ============================================================================
#pragma mark - Public API -
// ============================================================================

static void initialize()
{
    static bool isInitialized = false;
    if(!isInitialized)
    {
        isInitialized = true;
        kssc_initCursor(&g_stackCursor, NULL, NULL);
    }
}

static void setEnabled(bool isEnabled)
{
    if(isEnabled != g_isEnabled)
    {
        g_isEnabled = isEnabled;
        if(isEnabled)
        {
            initialize();

            ksid_generate(g_eventID);
            g_originalTerminateHandler = std::set_terminate(CPPExceptionTerminate);
        }
        else
        {
            std::set_terminate(g_originalTerminateHandler);
        }
        g_captureNextStackTrace = isEnabled;
    }
}

static bool isEnabled()
{
    return g_isEnabled;
}

extern "C" void kscm_enableSwapCxaThrow(void)
{
    if (g_cxaSwapEnabled != true)
    {
        ksct_swap(captureStackTrace);
        g_cxaSwapEnabled = true;
    }
}

extern "C" KSCrashMonitorAPI* kscm_cppexception_getAPI()
{
    static KSCrashMonitorAPI api =
    {
        .setEnabled = setEnabled,
        .isEnabled = isEnabled
    };
    return &api;
}
