//
//  KSCrashHandler.h
//
//  Created by Karl Stenerud on 12-02-12.
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


#ifndef HDR_KSCrashHandler_h
#define HDR_KSCrashHandler_h

#ifdef __cplusplus
extern "C" {
#endif


#include <mach/mach_types.h>
#include <signal.h>
#include <stdbool.h>


/** There are 3 ways an iOS app can crash (that we can capture):
 * - Mach kernel exception
 * - Fatal signal
 * - Uncaught Objective-C NSException
 */
typedef enum
{
    KSCrashTypeMachException = 1,
    KSCrashTypeSignal = 2,
    KSCrashTypeNSException = 4,
} KSCrashType;

#define KSCrashTypeAll (KSCrashTypeMachException | KSCrashTypeSignal | KSCrashTypeNSException)
#define KSCrashTypeAsyncSafe (KSCrashTypeMachException | KSCrashTypeSignal)

typedef enum
{
    KSCrashReservedThreadTypeMachPrimary,
    KSCrashReservedThreadTypeMachSecondary,
    KSCrashReservedThreadTypeCount
} KSCrashReservedTheadType;

typedef struct KSCrash_HandlerContext
{
    // Caller defined values. Caller must fill these out prior to initialization.

    /** Called by the crash handler when a crash is detected. */
    void (*onCrash)(void);


    // Implementation defined values. Caller does not initialize these.

    /** Threads reserved by the crash handlers, which must not be suspended. */
    thread_t reservedThreads[KSCrashReservedThreadTypeCount];

    /** If true, the crash handling system is currently handling a crash.
     * When false, all values below this field are considered invalid.
     */
    bool handlingCrash;

    /** If true, a second crash occurred while handling a crash. */
    bool crashedDuringCrashHandling;

    /** If true, the registers contain valid information about the crash. */
    bool registersAreValid;

    /** True if the crash system has detected a stack overflow. */
    bool isStackOverflow;

    /** The crashed thread. */
    thread_t crashedThread;

    /** Address that caused the fault. */
    uintptr_t faultAddress;

    /** The type of crash that occurred.
     * This determines which other fields are valid. */
    KSCrashType crashType;

    struct
    {
        /** The mach exception type. */
        int type;

        /** The mach exception code. */
        int64_t code;

        /** The mach exception subcode. */
        int64_t subcode;
    } mach;

    struct
    {
        /** The exception name. */
        const char* name;

        /** The exception reason. */
        const char* reason;

        /** The stack trace. */
        uintptr_t* stackTrace;

        /** Length of the stack trace. */
        int stackTraceLength;
    } NSException;

    struct
    {
        /** User context information. */
        const ucontext_t* userContext;

        /** Signal information. */
        const siginfo_t* signalInfo;
    } signal;

} KSCrash_HandlerContext;


/** Install crash handlers.
 *
 * @param context Contextual information for the crash handlers.
 *
 * @param crashTypes The crash types to install handlers for.
 *
 * @return which crash handlers were installed successfully.
 */
KSCrashType kscrash_handlers_installWithContext(KSCrash_HandlerContext* context,
                                                KSCrashType crashTypes);

/** Uninstall crash handlers.
 *
 * @param crashTypes The crash types to install handlers for.
 */
void kscrash_handlers_uninstall(KSCrashType crashTypes);

/** Suspend all non-reserved threads.
 *
 * Reserved threads include the current thread and all threads in
  "reservedThreads" in the context.
 */
void kscrash_handlers_suspendThreads(void);

/** Resume all non-reserved threads.
 *
 * Reserved threads include the current thread and all threads in
 * "reservedThreads" in the context.
 */
void kscrash_handlers_resumeThreads(void);


#ifdef __cplusplus
}
#endif

#endif // HDR_KSCrashHandler_h
