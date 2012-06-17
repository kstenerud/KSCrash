//
//  KSCrashContext.h
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


/* Contextual information about a crash.
 */


#ifndef HDR_KSCrashContext_h
#define HDR_KSCrashContext_h

#ifdef __cplusplus
extern "C" {
#endif


#include "KSReportWriter.h"

#include <mach/mach_types.h>
#include <signal.h>
#include <stdbool.h>


/** There are 3 ways an iOS app can crash (that we can capture):
 * - Mach kernel exception
 * - Uncaught Objective-C NSException
 * - Fatal signal
 */
typedef enum
{
    KSCrashTypeMachException,
    KSCrashTypeSignal,
    KSCrashTypeNSException,
} KSCrashType;

/** Contextual data used by the crash report writer.
 */
typedef struct
{
    /** A unique identifier (UUID). */
    const char* crashID;
    
    /** If true, the application has crashed. */
    volatile bool crashed;
    
    /** The type of crash that occurred.
     * This determines which other fields are valid. */
    KSCrashType crashType;
    
    /** The crashed thread (KSCrashTypeMachException only). */
    thread_t machCrashedThread;
    
    /** The mach exception type (KSCrashTypeMachException only). */
    int machExceptionType;
    
    /** The mach exception code (KSCrashTypeMachException only). */
    int64_t machExceptionCode;
    
    /** The mach exception subcode (KSCrashTypeMachException only). */
    int64_t machExceptionSubcode;
    
    /** The exception name (KSCrashTypeNSException only). */
    const char* NSExceptionName;
    
    /** The exception reason (KSCrashTypeNSException only). */
    const char* NSExceptionReason;
    
    /** The stack trace from NSException (KSCrashTypeNSException only). */
    uintptr_t* NSExceptionStackTrace;
    
    /** Length of the NSException stack trace (KSCrashTypeNSException only). */
    int NSExceptionStackTraceLength;
    
    /** User context information (KSCrashTypeSignal only). */
    const ucontext_t* signalUserContext;
    
    /** Signal information (KSCrashTypeSignal only). */
    const siginfo_t* signalInfo;
    
    /** Address that caused the fault. */
    uintptr_t faultAddress;
    
    /** True if the crash system has detected a stack overflow. */
    bool isStackOverflow;
    
    /** System information in JSON format (to be written to the report). */
    const char* systemInfoJSON;
    
    /** User information in JSON format (to be written to the report). */
    const char* userInfoJSON;
    
    /** Timestamp for when the app was launched (mach_absolute_time()) */
    uint64_t appLaunchTime;
    
    /** Timestamp for when the app state was last changed (active<-> inactive,
     * background<->foreground) (mach_absolute_time()) */
    uint64_t appStateTransitionTime;
    
    /** If true, the application is currently active. */
    bool applicationIsActive;
    
    /** If true, the application is currently in the foreground. */
    bool applicationIsInForeground;
    
    /** Total active time elapsed since the last crash. */
    double activeDurationSinceLastCrash;
    
    /** Total time backgrounded elapsed since the last crash. */
    double backgroundDurationSinceLastCrash;
    
    /** Number of app launches since the last crash. */
    int launchesSinceLastCrash;
    
    /** Number of sessions (launch, resume from suspend) since last crash. */
    int sessionsSinceLastCrash;
    
    /** Total active time elapsed since launch. */
    double activeDurationSinceLaunch;
    
    /** Total time backgrounded elapsed since launch. */
    double backgroundDurationSinceLaunch;
    
    /** Number of sessions (launch, resume from suspend) since app launch. */
    int sessionsSinceLaunch;
    
    /** If true, the application crashed on the previous launch. */
    bool crashedLastLaunch;
    
    /** When writing the crash report, print a stack trace to STDOUT as well. */
    bool printTraceToStdout;
    
    /** Allows the application the opportunity to add extra data to the report
     * file. Application MUST NOT call async-unsafe methods!
     */
    void(*onCrashNotify)(const KSReportWriter* writer);
} KSCrashContext;


#ifdef __cplusplus
}
#endif

#endif // HDR_KSCrashContext_h
