//
//  KSCrashHandler_NSException.m
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


#import "KSCrashHandler_NSException.h"

#import "KSCrashHandler_Common.h"
#import "KSLogger.h"
#import "KSMach.h"


// Avoiding static functions due to linker issues.

/** Our custom excepetion handler.
 * Fetch the stack trace from the exception and write a report.
 *
 * @param exception The exception that was raised.
 */
void kscrash_nsexc_handleException(NSException* exception);


/** Flag noting if we've installed our custom handlers or not.
 * It's not fully thread safe, but it's safer than locking and slightly better
 * than nothing.
 */
static volatile sig_atomic_t g_installed = 0;

/** The exception handler that was in place before we installed ours. */
static NSUncaughtExceptionHandler* g_previousUncaughtExceptionHandler;

/** Context to fill with crash information. */
static KSCrashContext* g_crashContext;


void kscrash_nsexc_handleException(NSException* exception)
{
    // This is as close to atomic test-and-set we can get on iOS since
    // iOS devices don't handle OSAtomicTestAndSetBarrier properly.
    static volatile sig_atomic_t called = 0;
    if(!called)
    {
        called = 1;
        
        kscrash_uninstallNSExceptionHandler();
        
        // Don't report if another handler has already.
        if(!g_crashContext->crashed)
        {
            // Note: We don't set g_crashContext->crashed here.
            
            // Save the NSException data.
            NSArray* addresses = [exception callStackReturnAddresses];
            NSUInteger numFrames = [addresses count];
            uintptr_t* callstack = malloc(numFrames * sizeof(*callstack));
            for(NSUInteger i = 0; i < numFrames; i++)
            {
                callstack[i] = [[addresses objectAtIndex:i] unsignedIntValue];
            }
            
            g_crashContext->crashType = KSCrashTypeNSException;
            g_crashContext->NSExceptionName = strdup([[exception name] UTF8String]);
            g_crashContext->NSExceptionReason = strdup([[exception reason] UTF8String]);
            g_crashContext->NSExceptionStackTrace = callstack;
            g_crashContext->NSExceptionStackTraceLength = (int)numFrames;
        }
        
        // This handler doesn't handle the crash directly. Rather, it aborts
        // and the signal handler does the rest (which is how the Apple crash
        // manager works also).
        abort();
        return; // Shouldn't really need this...
    }
    
    // Another thread threw an uncaught exception before we could restore the
    // old handler. Just log it and ignore it.
    KSLOG_ERROR(@"Called again before the original handler was restored: %@",
                exception);
}


void kscrash_installNSExceptionHandler(KSCrashContext* const context,
                                       void(*onCrash)())
{
    #pragma unused(onCrash)
    if(!g_installed)
    {
        // Guarding against double-calls is more important than guarding against
        // reciprocal calls.
        g_installed = 1;
        
        g_crashContext = context;
        
        g_previousUncaughtExceptionHandler = NSGetUncaughtExceptionHandler();
        NSSetUncaughtExceptionHandler(&kscrash_nsexc_handleException);
    }
}

void kscrash_uninstallNSExceptionHandler(void)
{
    if(g_installed)
    {
        // Guarding against double-calls is more important than guarding against
        // reciprocal calls.
        g_installed = 0;
        
        NSSetUncaughtExceptionHandler(g_previousUncaughtExceptionHandler);
    }
}
