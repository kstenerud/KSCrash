//
//  KSCrashReportC.h
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

/* Writes a crash report to disk.
 */

#ifndef HDR_KSCrashReport_h
#define HDR_KSCrashReport_h

#include <stdbool.h>

#import "KSCrashMonitorContext.h"
#import "KSCrashReportWriter.h"

#ifdef __cplusplus
extern "C" {
#endif

// ============================================================================
#pragma mark - Configuration -
// ============================================================================

/** Set custom user information to be stored in the report.
 *
 * @param userInfoJSON The user information, in JSON format.
 */
void kscrashreport_setUserInfoJSON(const char *const userInfoJSON);

/** Get a copy of the custom user information stored in the report.
 *
 * @return A JSON string representing the user information,
 *         or NULL if no information is set.
 *         The caller is responsible for freeing the returned string.
 */
const char *kscrashreport_getUserInfoJSON(void);

/** Configure whether to introspect any interesting memory locations.
 *  This can find things like strings or Objective-C classes.
 *
 * @param shouldIntrospectMemory If true, introspect memory.
 */
void kscrashreport_setIntrospectMemory(bool shouldIntrospectMemory);

/** Specify which objective-c classes should not be introspected.
 *
 * @param doNotIntrospectClasses Array of class names.
 * @param length Length of the array.
 */
void kscrashreport_setDoNotIntrospectClasses(const char **doNotIntrospectClasses, int length);

/** Set the function to call when writing the user section of the report.
 *  This allows the user to add more fields to the user section at the time of the crash.
 *  Note: Only async-safe functions are allowed in the callback.
 *
 * @param userSectionWriteCallback The user section write callback.
 */
void kscrashreport_setUserSectionWriteCallback(const KSReportWriteCallback userSectionWriteCallback);

// ============================================================================
#pragma mark - Main API -
// ============================================================================

/** Write a standard crash report to a file.
 *
 * @param monitorContext Contextual information about the crash and environment.
 *                       The caller must fill this out before passing it in.
 *
 * @param path The file to write to.
 */
void kscrashreport_writeStandardReport(const struct KSCrash_MonitorContext *const monitorContext, const char *path);

/** Write a minimal crash report to a file.
 *
 * @param monitorContext Contextual information about the crash and environment.
 *                       The caller must fill this out before passing it in.
 *
 * @param path The file to write to.
 */
void kscrashreport_writeRecrashReport(const struct KSCrash_MonitorContext *const monitorContext, const char *path);

#ifdef __cplusplus
}
#endif

#endif  // HDR_KSCrashReport_h
