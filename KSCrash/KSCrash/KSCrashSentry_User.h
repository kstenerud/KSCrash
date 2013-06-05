//
//  KSCrashSentry_User.h
//  KSCrash
//
//  Created by Karl Stenerud on 6/4/13.
//  Copyright (c) 2013 Karl Stenerud. All rights reserved.
//

#ifndef HDR_KSCrashSentry_User_h
#define HDR_KSCrashSentry_User_h

#ifdef __cplusplus
extern "C" {
#endif


#include "KSCrashSentry.h"

#include <signal.h>
#include <stdbool.h>


/** Install the user exception handler.
 *
 * @param context Contextual information for the crash handler.
 *
 * @return true if installation was succesful.
 */
bool kscrashsentry_installUserExceptionHandler(KSCrash_SentryContext* context);

/** Uninstall the user exception handler.
 */
void kscrashsentry_uninstallUserExceptionHandler(void);


/** Report a custom, user defined exception.
 * If terminateProgram is true, all sentries will be uninstalled and the application will
 * terminate with an abort().
 *
 * @param name The exception name (for namespacing exception types).
 *
 * @param reason A description of why the exception occurred.
 *
 * @param lineOfCode A copy of the offending line of code (NULL = ignore).
 *
 * @param stackTrace An array of strings representing the call stack leading to the exception.
 *
 * @param stackTraceCount The length of the stack trace array.
 *
 * @param terminateProgram If true, do not return from this function call. Terminate the program instead.
 */
void kscrashsentry_reportUserException(const char* name,
                                       const char* reason,
                                       const char* lineOfCode,
                                       const char** stackTrace,
                                       size_t stackTraceCount,
                                       bool terminateProgram);


#ifdef __cplusplus
}
#endif

#endif // HDR_KSCrashSentry_User_h
