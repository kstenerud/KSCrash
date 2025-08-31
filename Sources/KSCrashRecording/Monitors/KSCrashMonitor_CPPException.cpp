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

#include "KSCompilerDefines.h"
#include "KSCrashMonitorContext.h"
#include "KSCrashMonitorHelper.h"
#include "KSID.h"
#include "KSMachineContext.h"
#include "KSStackCursor_SelfThread.h"
#include "KSThread.h"

// #define KSLogger_LocalLevel TRACE
#include <cxxabi.h>
#include <dlfcn.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include <exception>
#include <string>
#include <typeinfo>

#include "KSCxaThrowSwapper.h"
#include "KSLogger.h"

#define STACKTRACE_BUFFER_LENGTH 30
#define DESCRIPTION_BUFFER_LENGTH 1000

// Compiler hints for "if" statements
#define likely_if(x) if (__builtin_expect(x, 1))
#define unlikely_if(x) if (__builtin_expect(x, 0))

// ============================================================================
#pragma mark - Globals -
// ============================================================================

static struct {
    std::atomic<KSCM_InstalledState> installedState { KSCM_NotInstalled };
    std::atomic<bool> isEnabled { false };

    /** True if the handler should capture the next stack trace. */
    bool captureNextStackTrace = false;

    bool cxaSwapEnabled = false;

    std::terminate_handler originalTerminateHandler;

    KSCrash_ExceptionHandlerCallbacks callbacks;
} g_state;

static thread_local KSStackCursor g_stackCursor;

static bool isEnabled(void) { return g_state.isEnabled && g_state.installedState == KSCM_Installed; }

// ============================================================================
#pragma mark - Callbacks -
// ============================================================================

static KS_NOINLINE void captureStackTrace(void *, std::type_info *tinfo,
                                          void (*)(void *)) KS_KEEP_FUNCTION_IN_STACKTRACE
{
    if (tinfo != nullptr && strcmp(tinfo->name(), "NSException") == 0) {
        return;
    }
    if (g_state.captureNextStackTrace) {
        kssc_initSelfThread(&g_stackCursor, 2);
    }
    KS_THWART_TAIL_CALL_OPTIMISATION
}

typedef void (*cxa_throw_type)(void *, std::type_info *, void (*)(void *));

extern "C" {
void __cxa_throw(void *thrown_exception, std::type_info *tinfo, void (*dest)(void *)) __attribute__((weak));

void __cxa_throw(void *thrown_exception, std::type_info *tinfo, void (*dest)(void *)) KS_KEEP_FUNCTION_IN_STACKTRACE
{
    static cxa_throw_type orig_cxa_throw = NULL;
    if (g_state.cxaSwapEnabled == false) {
        captureStackTrace(thrown_exception, tinfo, dest);
    }
    unlikely_if(orig_cxa_throw == NULL) { orig_cxa_throw = (cxa_throw_type)dlsym(RTLD_NEXT, "__cxa_throw"); }
    orig_cxa_throw(thrown_exception, tinfo, dest);
    KS_THWART_TAIL_CALL_OPTIMISATION
    __builtin_unreachable();
}
}

static const char *cpp_demangleSymbol(const char *mangledSymbol)
{
    int status = 0;
    static char stackBuffer[DESCRIPTION_BUFFER_LENGTH] = { 0 };
    size_t length = DESCRIPTION_BUFFER_LENGTH;
    char *demangled = __cxxabiv1::__cxa_demangle(mangledSymbol, stackBuffer, &length, &status);
    return demangled != nullptr && status == 0 ? demangled : mangledSymbol;
}

static void CPPExceptionTerminate(void)
{
    KSLOG_DEBUG("Trapped c++ exception");
    std::type_info *tinfo = __cxxabiv1::__cxa_current_exception_type();
    const char *name = cpp_demangleSymbol(tinfo->name());
    if (name != NULL && strcmp(name, "NSException") == 0) {
        KSLOG_DEBUG("Detected NSException. Letting the current NSException handler deal with it.");
        goto skip_handling;
    }

    if (isEnabled()) {
        thread_t thisThread = (thread_t)ksthread_self();
        // This requires async-safety because the environment is suspended.
        KSCrash_MonitorContext *crashContext = g_state.callbacks.notify(
            thisThread,
            (KSCrash_ExceptionHandlingRequirements) {
                .asyncSafety = true, .isFatal = true, .shouldRecordAllThreads = true, .shouldWriteReport = true });
        if (crashContext->requirements.shouldExitImmediately) {
            goto skip_handling;
        }

        char descriptionBuff[DESCRIPTION_BUFFER_LENGTH] = { 0 };
        const char *description = descriptionBuff;

        KSLOG_DEBUG("Discovering what kind of exception was thrown.");
        g_state.captureNextStackTrace = false;

        // We need to be very explicit about what type is thrown or it'll drop through.
        try {
            throw;
        } catch (std::exception *exc) {
            snprintf(descriptionBuff, sizeof(descriptionBuff), "%s", exc->what());
        } catch (std::exception &exc) {
            snprintf(descriptionBuff, sizeof(descriptionBuff), "%s", exc.what());
        } catch (std::string *exc) {
            snprintf(descriptionBuff, sizeof(descriptionBuff), "%s", exc->c_str());
        } catch (std::string &exc) {
            snprintf(descriptionBuff, sizeof(descriptionBuff), "%s", exc.c_str());
        }
#define CATCH_VALUE(TYPE, PRINTFTYPE) \
    catch (TYPE value) { snprintf(descriptionBuff, sizeof(descriptionBuff), "%" #PRINTFTYPE, value); }
        CATCH_VALUE(char, d)
        CATCH_VALUE(short, d)
        CATCH_VALUE(int, d)
        CATCH_VALUE(long, ld)
        CATCH_VALUE(long long, lld)
        CATCH_VALUE(unsigned char, u)
        CATCH_VALUE(unsigned short, u)
        CATCH_VALUE(unsigned int, u)
        CATCH_VALUE(unsigned long, lu)
        CATCH_VALUE(unsigned long long, llu)
        CATCH_VALUE(float, f)
        CATCH_VALUE(double, f)
        CATCH_VALUE(long double, Lf)
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wexceptions"
        CATCH_VALUE(char *, s)
        CATCH_VALUE(const char *, s)
#pragma clang diagnostic pop
        catch (...) { description = NULL; }
        g_state.captureNextStackTrace = isEnabled();

        // TODO: Should this be done here? Maybe better in the exception handler?
        KSMachineContext machineContext = { 0 };
        ksmc_getContextForThread(thisThread, &machineContext, true);

        KSLOG_DEBUG("Filling out context.");
        kscm_fillMonitorContext(crashContext, kscm_cppexception_getAPI());
        crashContext->registersAreValid = false;
        crashContext->stackCursor = &g_stackCursor;
        crashContext->CPPException.name = name;
        crashContext->exceptionName = name;
        crashContext->crashReason = description;
        crashContext->offendingMachineContext = &machineContext;

        g_state.callbacks.handle(crashContext);
    }

    KSLOG_DEBUG("Calling original terminate handler.");
skip_handling:
    g_state.originalTerminateHandler();
}

static void install()
{
    KSCM_InstalledState expectedState = KSCM_NotInstalled;
    if (!atomic_compare_exchange_strong(&g_state.installedState, &expectedState, KSCM_Installed)) {
        return;
    }

    kssc_initCursor(&g_stackCursor, NULL, NULL);
    g_state.originalTerminateHandler = std::set_terminate(CPPExceptionTerminate);
}

// ============================================================================
#pragma mark - Public API -
// ============================================================================

static const char *monitorId() { return "CPPException"; }

static KSCrashMonitorFlag monitorFlags() { return KSCrashMonitorFlagNone; }

static void setEnabled(bool enabled)
{
    bool expectedState = !enabled;
    if (!atomic_compare_exchange_strong(&g_state.isEnabled, &expectedState, enabled)) {
        // We were already in the expected state
        return;
    }

    if (enabled) {
        install();
    }
    g_state.captureNextStackTrace = isEnabled();
}

extern "C" void kscm_enableSwapCxaThrow(void)
{
    if (g_state.cxaSwapEnabled != true) {
        ksct_swap(captureStackTrace);
        g_state.cxaSwapEnabled = true;
    }
}

static void init(KSCrash_ExceptionHandlerCallbacks *callbacks) { g_state.callbacks = *callbacks; }

extern "C" KSCrashMonitorAPI *kscm_cppexception_getAPI()
{
    static KSCrashMonitorAPI api = { 0 };
    if (kscma_initAPI(&api)) {
        api.init = init;
        api.monitorId = monitorId;
        api.monitorFlags = monitorFlags;
        api.setEnabled = setEnabled;
        api.isEnabled = isEnabled;
    }
    return &api;
}
