//
//  KSCrashC.h
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


/* Primary C entry point into the crash reporting system.
 */


#ifndef HDR_KSCrashC_h
#define HDR_KSCrashC_h

#ifdef __cplusplus
extern "C" {
#endif


#include "KSCrashContext.h"

#include <stdbool.h>


/** Install the crash reporter. The reporter will record the next crash and then
 * terminate the program.
 *
 * @param crashReportFilePath The file to store the next crash report to.
 *
 * @param recrashReportFilePath If the system crashes during crash handling,
 *                              store a second, minimal report here.
 *
 * @param stateFilePath File to store persistent state in.
 *
 * @param crashID The unique identifier to assign to the next crash report.
 *
 * @param userInfoJSON Pre-baked JSON containing user-supplied information.
 *                     NULL = ignore.
 *
 * @param zombieCacheSize The size of the cache to use for zombie tracking.
 *                        Must be a power-of-2. 0 = no zombie tracking.
 *                        You should profile your app to see how many objects
 *                        are being allocated when choosing this value, but
 *                        generally you should use 16384 or higher. Uses 8 bytes
 *                        per cache entry.
 *
 * @param deadlockWatchdogInterval The interval in seconds between checks for
 *                                 deadlocks on the main thread. 0 = ignore.
 *
 * @param printTraceToStdout If true, print a stack trace to STDOUT when the app
 *                           crashes.
 *
 * @param onCrashNotify Function to call during a crash report to give the
 *                      callee an opportunity to add to the report.
 *                      NULL = ignore.
 *                      WARNING: Only call async-safe functions from this
 *                               function!
 *                               DO NOT call Objective-C methods!!!
 *
 * @return true if installation was successful.
 */
bool kscrash_install(const char* const crashReportFilePath,
                     const char* const recrashReportFilePath,
                     const char* stateFilePath,
                     const char* crashID,
                     const char* userInfoJSON,
                     unsigned int zombieCacheSize,
                     float deadlockWatchdogInterval,
                     bool printTraceToStdout,
                     KSReportWriteCallback onCrashNotify);

/** Set the user-supplied data in JSON format.
 *
 * @param userInfoJSON Pre-baked JSON containing user-supplied information.
 *                     NULL = delete.
 */
void kscrash_setUserInfoJSON(const char* const userInfoJSON);

/** Set the callback to invoke upon a crash.
 *
 * @param onCrashNotify Function to call during a crash report to give the
 *                      callee an opportunity to add to the report.
 *                      NULL = ignore.
 *                      WARNING: Only call async-safe functions from this
 *                               function!
 *                               DO NOT call Objective-C methods!!!
 */
void kscrash_setCrashNotifyCallback(const KSReportWriteCallback onCrashNotify);


#ifdef __cplusplus
}
#endif

#endif // HDR_KSCrashC_h
