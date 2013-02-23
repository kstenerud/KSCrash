//
//  KSCrashContext.h
//
//  Created by Karl Stenerud on 2012-01-28.
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


#include "KSCrashReportWriter.h"
#include "KSCrashSentry.h"
#include "KSCrashState.h"

#include <signal.h>
#include <stdbool.h>


typedef struct
{
    /** A unique identifier (UUID). */
    const char* crashID;

    /** Name of this process. */
    const char* processName;

    /** System information in JSON format (to be written to the report). */
    const char* systemInfoJSON;

    /** User information in JSON format (to be written to the report). */
    const char* userInfoJSON;

    /** When writing the crash report, print a stack trace to STDOUT as well. */
    bool printTraceToStdout;

    /** Callback allowing the application the opportunity to add extra data to
     * the report file. Application MUST NOT call async-unsafe methods!
     */
    KSReportWriteCallback onCrashNotify;
} KSCrash_Configuration;

/** Contextual data used by the crash report writer.
 */
typedef struct
{
    KSCrash_Configuration config;
    KSCrash_State state;
    KSCrash_SentryContext crash;
} KSCrash_Context;


#ifdef __cplusplus
}
#endif

#endif // HDR_KSCrashContext_h
