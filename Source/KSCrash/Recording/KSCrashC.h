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
 * @return The crash types that are being handled.
 */
KSCrashType kscrash_install(const char* const crashReportFilePath,
                            const char* const recrashReportFilePath,
                            const char* stateFilePath,
                            const char* crashID);

/** Set the crash types that will be handled.
 * Some crash types may not be enabled depending on circumstances (e.g. running
 * in a debugger).
 *
 * @param crashTypes The crash types to handle.
 *
 * @return The crash types that are now behing handled. If KSCrash has been
 *         installed, the return value represents the crash sentries that were
 *         successfully installed. Otherwise it represents which sentries it
 *         will attempt to activate when KSCrash installs.
 */
KSCrashType kscrash_setHandlingCrashTypes(KSCrashType crashTypes);

/** Reinstall the crash reporter. Useful for resetting the crash reporter
 * after a "soft" crash.
 *
 * @param crashReportFilePath The file to store the next crash report to.
 *
 * @param recrashReportFilePath If the system crashes during crash handling,
 *                              store a second, minimal report here.
 *
 * @param stateFilePath File to store persistent state in.
 *
 * @param crashID The unique identifier to assign to the next crash report.
 */
void kscrash_reinstall(const char* const crashReportFilePath,
                       const char* const recrashReportFilePath,
                       const char* const stateFilePath,
                       const char* const crashID);

/** Set the user-supplied data in JSON format.
 *
 * @param userInfoJSON Pre-baked JSON containing user-supplied information.
 *                     NULL = delete.
 */
void kscrash_setUserInfoJSON(const char* const userInfoJSON);

/** Set the maximum time to allow the main thread to run without returning.
 * If a task occupies the main thread for longer than this interval, the
 * watchdog will consider the queue deadlocked and shut down the app and write a
 * crash report.
 *
 * Warning: Make SURE that nothing in your app that runs on the main thread takes
 * longer to complete than this value or it WILL get shut down! This includes
 * your app startup process, so you may need to push app initialization to
 * another thread, or perhaps set this to a higher value until your application
 * has been fully initialized.
 *
 * 0 = Disabled.
 *
 * Default: 0
 */
void kscrash_setDeadlockWatchdogInterval(double deadlockWatchdogInterval);

/** Set whether or not to print a stack trace to stdout when a crash occurs.
 *
 * Default: false
 */
void kscrash_setPrintTraceToStdout(bool printTraceToStdout);

/** If true, search for thread names where appropriate.
 * Thread name searching is not async-safe, and so comes with the risk of
 * timing out and panicking in thread_lock().
 */
void kscrash_setSearchThreadNames(bool shouldSearchThreadNames);

/** If true, search for dispatch queue names where appropriate.
* Queue name searching is not async-safe, and so comes with the risk of
* timing out and panicking in thread_lock().
*/
void kscrash_setSearchQueueNames(bool shouldSearchQueueNames);

/** If true, introspect memory contents during a crash.
 * Any Objective-C objects or C strings near the stack pointer or referenced by
 * cpu registers or exceptions will be recorded in the crash report, along with
 * their contents.
 *
 * Default: false
 */
void kscrash_setIntrospectMemory(bool introspectMemory);

/** If true, monitor all Objective-C/Swift deallocations and keep track of any
 * accesses after deallocation.
 *
 * Default: false
 */
void kscrash_setCatchZombies(bool catchZombies);

/** List of Objective-C classes that should never be introspected.
 * Whenever a class in this list is encountered, only the class name will be recorded.
 * This can be useful for information security concerns.
 *
 * Default: NULL
 */
void kscrash_setDoNotIntrospectClasses(const char** doNotIntrospectClasses, size_t length);

/** Set the callback to invoke upon a crash.
 *
 * WARNING: Only call async-safe functions from this function! DO NOT call
 * Objective-C methods!!!
 *
 * @param onCrashNotify Function to call during a crash report to give the
 *                      callee an opportunity to add to the report.
 *                      NULL = ignore.
 *
 * Default: NULL
 */
void kscrash_setCrashNotifyCallback(const KSReportWriteCallback onCrashNotify);

/** Report a custom, user defined exception.
 * This can be useful when dealing with scripting languages.
 *
 * If terminateProgram is true, all sentries will be uninstalled and the application will
 * terminate with an abort().
 *
 * @param name The exception name (for namespacing exception types).
 *
 * @param reason A description of why the exception occurred.
 *
 * @param language A unique language identifier.
 *
 * @param lineOfCode A copy of the offending line of code (NULL = ignore).
 *
 * @param stackTrace An array of strings representing the call stack leading to the exception.
 *
 * @param stackTraceCount The length of the stack trace array (0 = ignore).
 *
 * @param terminateProgram If true, do not return from this function call. Terminate the program instead.
 */
void kscrash_reportUserException(const char* name,
                                 const char* reason,
                                 const char* language,
                                 const char* lineOfCode,
                                 const char** stackTrace,
                                 size_t stackTraceCount,
                                 bool terminateProgram);

#ifdef __cplusplus
}
#endif

#endif // HDR_KSCrashC_h
