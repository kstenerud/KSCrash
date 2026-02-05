//
//  KSCrashMonitor_User.c
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

#include "KSCrashMonitor_User.h"

#include "KSCompilerDefines.h"
#include "KSCrashMonitorContext.h"
#include "KSCrashMonitorHelper.h"
#include "KSID.h"
#include "KSStackCursor_SelfThread.h"
#include "KSThread.h"

// #define KSLogger_LocalLevel TRACE
#include <memory.h>
#include <stdlib.h>

#include "KSLogger.h"

/** Context to fill with crash information. */

static volatile bool g_isEnabled = false;

static KSCrash_ExceptionHandlerCallbacks g_callbacks;

void kscm_reportUserException(const char *name, const char *reason, const char *language, const char *lineOfCode,
                              const char *stackTrace, bool logAllThreads,
                              bool terminateProgram) KS_KEEP_FUNCTION_IN_STACKTRACE
{
    if (!g_isEnabled) {
        KSLOG_WARN("User-reported exception monitor is not installed. Exception has not been recorded.");
        return;
    }

    thread_t thisThread = (thread_t)ksthread_self();
    KSCrash_MonitorContext *ctx = g_callbacks.notify(
        thisThread, (KSCrash_ExceptionHandlingRequirements) { .asyncSafety = false,
                                                              .isFatal = terminateProgram,
                                                              .shouldRecordAllThreads = logAllThreads,
                                                              .shouldWriteReport = true });
    if (ctx->requirements.shouldExitImmediately) {
        goto exit_immediately;
    }

    KSMachineContext machineContext = { 0 };
    ksmc_getContextForThread(thisThread, &machineContext, true);
    KSStackCursor stackCursor;
    kssc_initSelfThread(&stackCursor, 3);

    KSLOG_DEBUG("Filling out context.");
    kscm_fillMonitorContext(ctx, kscm_user_getAPI());
    ctx->offendingMachineContext = &machineContext;
    ctx->registersAreValid = false;
    ctx->crashReason = reason;
    ctx->userException.name = name;
    ctx->userException.language = language;
    ctx->userException.lineOfCode = lineOfCode;
    ctx->userException.customStackTrace = stackTrace;
    ctx->stackCursor = &stackCursor;
    ctx->currentSnapshotUserReported = true;

    g_callbacks.handle(ctx);

exit_immediately:
    if (terminateProgram) {
        kscm_exit(1, kscexc_requiresAsyncSafety(ctx->requirements));
    }

    KS_THWART_TAIL_CALL_OPTIMISATION
}

static const char *monitorId(__unused void *context) { return "UserReported"; }

static void setEnabled(bool isEnabled, __unused void *context) { g_isEnabled = isEnabled; }

static bool isEnabled(__unused void *context) { return g_isEnabled; }

static void init(KSCrash_ExceptionHandlerCallbacks *callbacks, __unused void *context) { g_callbacks = *callbacks; }

KSCrashMonitorAPI *kscm_user_getAPI(void)
{
    static KSCrashMonitorAPI api = { 0 };
    if (kscma_initAPI(&api)) {
        api.init = init;
        api.monitorId = monitorId;
        api.setEnabled = setEnabled;
        api.isEnabled = isEnabled;
    }
    return &api;
}
