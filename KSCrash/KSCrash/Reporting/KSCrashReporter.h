//
//  KSCrashReporterC.h
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


/* Primary C entry point into the crash reporting system.
 */


#ifndef HDR_KSCrashReporterC_h
#define HDR_KSCrashReporterC_h

#ifdef __cplusplus
extern "C" {
#endif


#include "KSCrashContext.h"

#include <stdbool.h>


/** Install the crash reporter. The reporter will record the next crash and then
 * terminate the program.
 *
 * @param reportFilePath The file to store the next crash report to.
 *
 * @param stateFilePath File to store persistent state in.
 *
 * @param crashID The unique identifier to assign to the next crash report.
 *
 * @param userInfoJSON Pre-baked JSON containing user-supplied information.
 *                     NULL = ignore.
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
bool kscrash_installReporter(const char* reportFilePath,
                             const char* stateFilePath,
                             const char* crashID,
                             const char* userInfoJSON,
                             bool printTraceToStdout,
                             KSReportWriteCallback onCrashNotify);

/** Set the user-supplied data in JSON format.
 *
 * @param userInfoJSON Pre-baked JSON containing user-supplied information.
 *                     NULL = delete.
 */
void kscrash_setUserInfoJSON(const char* const userInfoJSON);

#ifdef __cplusplus
}
#endif

#endif // HDR_KSCrashReporterC_h
