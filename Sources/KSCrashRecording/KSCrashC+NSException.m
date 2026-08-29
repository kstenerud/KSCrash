//
//  KSCrashC+NSException.m
//
//  Created by Alexander Cohen on 2026-08-22.
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

#import <Foundation/Foundation.h>
#import <stdatomic.h>

#import "KSCompilerDefines.h"
#import "KSCrashC.h"
#import "KSCrashMonitor_NSException+Private.h"
#import "KSLogger.h"

// The NSException monitor hands over its reporter when it is enabled; the
// entry point below is the only consumer. Written by monitor enable and read
// from any reporting thread, so the handoff is an acquire/release atomic.
static KSCrashCustomNSExceptionReporter *_Atomic g_reporter;

static void onNSExceptionHandlingEnabled(__unused NSUncaughtExceptionHandler *uncaughtExceptionHandler,
                                         KSCrashCustomNSExceptionReporter *reporter)
{
    atomic_store_explicit(&g_reporter, reporter, memory_order_release);
}

__attribute__((constructor)) static void kscrash_nsexception_register(void)
{
    kscm_nsexception_setOnEnabledHandler(onNSExceptionHandlingEnabled);
}

void kscrash_reportNSException(NSException *exception, bool logAllThreads,
                               int extraSkipFrames) KS_KEEP_FUNCTION_IN_STACKTRACE
{
    KSCrashCustomNSExceptionReporter *reporter = atomic_load_explicit(&g_reporter, memory_order_acquire);
    if (reporter == NULL) {
        KSLOG_WARN("The NSException monitor is not enabled; the exception is not reported.");
        return;
    }
    reporter(exception, logAllThreads, extraSkipFrames);
    KS_THWART_TAIL_CALL_OPTIMISATION
}
