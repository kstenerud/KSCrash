//
//  KSCrashMonitor_Watchdog.h
//
//  Created by Alexander Cohen on 2025-11-04.
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

/* Catches Hangs and Watchdog timeouts.
 */

#ifndef HDR_KSCrashMonitor_Watchdog_h
#define HDR_KSCrashMonitor_Watchdog_h

#ifdef __cplusplus
extern "C" {
#endif

#include <stdbool.h>

#include "KSCrashMonitorAPI.h"
#include "KSCrashNamespace.h"

/** Access the Monitor API.
 */
KSCrashMonitorAPI *kscm_watchdog_getAPI(void);

/** Returns a string for a specified role..
 */
const char *kscm_stringFromRole(int /*task_role_t*/ role);

#ifdef __cplusplus
}
#endif

#endif  // HDR_KSCrashMonitor_Watchdog_h
