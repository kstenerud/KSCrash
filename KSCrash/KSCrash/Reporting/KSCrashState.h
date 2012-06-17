//
//  KSCrashState.h
//
//  Created by Karl Stenerud on 12-02-05.
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


/* Manages persistent state information useful for crash reporting such as
 * number of sessions, session length, etc.
 */

#ifndef HDR_KSCrashState_h
#define HDR_KSCrashState_h

#ifdef __cplusplus
extern "C" {
#endif


#include "KSCrashContext.h"

#include <stdbool.h>


/** Initialize the state monitor.
 *
 * @param stateFilePath Where to store state information.
 *
 * @param context The crash context.
 *
 * @return true if initialization was successful.
 */
bool kscrash_initState(const char* stateFilePath, KSCrashContext* context);

/** Notify the crash reporter of the application active state.
 *
 * @param isActive true if the application is active, otherwise false.
 */
void kscrash_notifyApplicationActive(bool isActive);

/** Notify the crash reporter of the application foreground/background state.
 *
 * @param isActive true if the application is in the foreground, false if
 *                 it is in the background.
 */
void kscrash_notifyApplicationInForeground(bool isInForeground);

/** Notify the crash reporter that the application is terminating.
 */
void kscrash_notifyApplicationTerminate(void);

/** Notify the crash reporter that the application has crashed.
 */
void kscrash_notifyApplicationCrash(void);


#ifdef __cplusplus
}
#endif

#endif // HDR_KSCrashState_h
